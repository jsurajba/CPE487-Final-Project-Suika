library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.suika_pkg.all;

entity physics_engine is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;

        -- One-cycle pulse per VSYNC from game_controller
        frame_tick      : in  std_logic;

        -- Spawn request from game controller (drop a fruit from the top)
        spawn_req       : in  std_logic;
        spawn_x         : in  unsigned(10 downto 0);
        spawn_type      : in  unsigned(3 downto 0);

        -- Outputs
        fruits_out      : out fruit_array_t;
        busy            : out std_logic;
        gameover        : out std_logic;
        score_pulse     : out std_logic;
        score_value     : out unsigned(7 downto 0);
        spawn_accepted  : out std_logic;
        fruit_in_flight : out std_logic
    );
end entity;

architecture rtl of physics_engine is

    type state_t is (
        S_IDLE,
        S_PREDICT,         -- save pos, apply gravity + old vel -> predicted pos
        S_WALLS,           -- positional wall/floor constraints
        S_COL_OUTER,       -- outer loop: find next active i
        S_COL_INNER_LOAD,  -- 1-cycle pipeline break before multiply
        S_COL_CHECK,       -- compute dist^2, check overlap
        S_COL_RESPOND,     -- positional separation (NO velocity changes)
        S_COL_MERGE,       -- spawn merged fruit
        S_DONE,            -- iteration gate: repeat S_WALLS..S_DONE, then derive
        S_DERIVE_VEL,      -- vel = (current_pos - prev_pos); apply mild damping
        S_GAMEOVER_CHK,    -- scan for settled fruit above the game-over line
        S_SPAWN_SCAN       -- place a newly dropped fruit in the first free slot
    );
    signal state : state_t := S_IDLE;

    signal fruits : fruit_array_t := (others => FRUIT_NULL);

    ---------------------------------------------------------------------------
    -- Previous-position arrays for PBD velocity derivation.
    -- Set at the start of S_PREDICT; used at the end of S_DERIVE_VEL.
    -- Wall contacts update x_prev / y_prev to zero velocity on that axis.
    ---------------------------------------------------------------------------
    type pos_array_t is array(0 to MAX_FRUITS-1) of fixed_t;
    signal x_prev : pos_array_t := (others => (others => '0'));
    signal y_prev : pos_array_t := (others => (others => '0'));

    signal i_idx : integer range 0 to MAX_FRUITS := 0;
    signal j_idx : integer range 0 to MAX_FRUITS := 0;

    -- Collision info latched from S_COL_CHECK into S_COL_RESPOND
    signal pair_dx    : signed(16 downto 0) := (others => '0');
    signal pair_dy    : signed(16 downto 0) := (others => '0');
    signal pair_r_sum : integer range 0 to 4095 := 0;

    -- Merge staging
    signal merge_pending : std_logic := '0';
    signal merge_x       : fixed_t   := (others => '0');
    signal merge_y       : fixed_t   := (others => '0');
    signal merge_type    : unsigned(3 downto 0) := (others => '0');

    -- Spawn request latch
    signal spawn_latched : std_logic := '0';
    signal spawn_x_lat   : unsigned(10 downto 0) := (others => '0');
    signal spawn_t_lat   : unsigned(3 downto 0)  := (others => '0');

    signal gameover_reg  : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Grace timer.  Set to GRACE_FRAMES on a player-drop; 0 for merged fruits.
    -- Decremented each frame in S_PREDICT.
    -- Gameover check is suppressed while grace > 0 (fruit is entering the jar).
    ---------------------------------------------------------------------------
    constant GRACE_FRAMES : integer := 45;
    type grace_array_t is array(0 to MAX_FRUITS-1) of unsigned(6 downto 0);
    signal grace_cnt : grace_array_t := (others => (others => '0'));

    ---------------------------------------------------------------------------
    -- Solver iteration count.  0 = first pass; repeat up to MAX_ITER total.
    -- More passes = stiffer stack, better resolved overlaps.
    -- 3 passes is a good tradeoff on this hardware budget.
    ---------------------------------------------------------------------------
    constant MAX_ITER : integer := 2;   -- 0, 1, 2 = 3 total passes
    signal col_iter   : integer range 0 to MAX_ITER := 0;

    signal score_pulse_r : std_logic := '0';
    signal score_value_r : unsigned(7 downto 0) := (others => '0');

begin

    fruits_out  <= fruits;
    busy        <= '0' when state = S_IDLE else '1';
    gameover    <= gameover_reg;
    score_pulse <= score_pulse_r;
    score_value <= score_value_r;

    ---------------------------------------------------------------------------
    -- Combinational: is any fruit still visibly in motion?
    -- Used by the renderer / game controller as a "settle" indicator.
    ---------------------------------------------------------------------------
    process(grace_cnt, fruits)
    begin
        fruit_in_flight <= '0';
        for k in 0 to MAX_FRUITS-1 loop
            if fruits(k).active = '1' and
               (grace_cnt(k) /= 0 or
                abs(fp_to_int(fruits(k).vy)) > 0 or
                abs(fp_to_int(fruits(k).vx)) > 0) then
                fruit_in_flight <= '1';
            end if;
        end loop;
    end process;

    ---------------------------------------------------------------------------
    -- Main FSM
    ---------------------------------------------------------------------------
    process(clk)
        variable vy_eff                        : fixed_t;
        variable r_i, r_j                      : integer;
        variable r_sum, r_sum_sq, dist_sq      : integer;
        variable dx_i, dy_i                    : integer;
        variable abs_dx_v, abs_dy_v            : integer;
        variable dist_approx, penetration      : integer;
        variable px, py                        : integer;
        variable new_vx, new_vy                : fixed_t;
        variable fr_left, fr_right, fr_bot     : fixed_t;
        variable placed                        : boolean;
        variable settled                       : std_logic;
    begin
        if rising_edge(clk) then

            score_pulse_r  <= '0';
            spawn_accepted <= '0';

            -- Latch spawn request (cleared by S_SPAWN_SCAN)
            if rst = '1' then
                spawn_latched <= '0';
            elsif spawn_req = '1' then
                spawn_latched <= '1';
                spawn_x_lat   <= spawn_x;
                
                -- THE FIX: Prevent Out-of-Bounds indexing!
                -- Assuming NUM_TYPES is 11 (0 to 10)
                if to_integer(spawn_type) >= NUM_TYPES then
                    spawn_t_lat <= (others => '0'); -- Default to cherry if garbage data arrives
                else
                    spawn_t_lat <= spawn_type;
                end if;
            end if;

            if rst = '1' then
                state         <= S_IDLE;
                fruits        <= (others => FRUIT_NULL);
                x_prev        <= (others => (others => '0'));
                y_prev        <= (others => (others => '0'));
                grace_cnt     <= (others => (others => '0'));
                i_idx         <= 0;
                j_idx         <= 0;
                merge_pending <= '0';
                gameover_reg  <= '0';
                col_iter      <= 0;

            else
                case state is

                    ----------------------------------------------------------
                    when S_IDLE =>
                        if gameover_reg = '0' and frame_tick = '1' then
                            state <= S_PREDICT;
                            i_idx <= 0;
                        elsif gameover_reg = '0' and spawn_latched = '1' then
                            -- Suika rule: only accept the next drop once every
                            -- active fruit has settled.  With PBD, wall contact
                            -- immediately zeroes velocity so fruits settle in
                            -- the same frame they land.  Check raw Q12.4 units
                            -- (> 4 = > 0.25 px/frame) to catch slow-moving fruit
                            -- that fp_to_int would round to 0.
                            settled := '1';
                            for k in 0 to MAX_FRUITS-1 loop
                                if fruits(k).active = '1' and
                                   (grace_cnt(k) /= 0 or
                                    abs(to_integer(fruits(k).vy)) > 4 or
                                    abs(to_integer(fruits(k).vx)) > 4) then
                                    settled := '0';
                                end if;
                            end loop;
                            if settled = '1' then
                                state          <= S_SPAWN_SCAN;
                                spawn_accepted <= '1';
                            end if;
                        end if;

                    ----------------------------------------------------------
                    -- PBD STEP 1: Save position snapshot; apply external forces
                    --             (gravity) + stored velocity to predict new pos.
                    --             Stored velocity is from last frame's DERIVE_VEL.
                    --
                    -- NOTE: We do NOT change vx/vy here for horizontal - air drag
                    --       is applied in DERIVE_VEL so it shows up correctly in
                    --       the velocity that PREDICT reads next frame.
                    --       For vy we add gravity and store the result so that
                    --       DERIVE_VEL and the gameover check see a sensible value.
                    ----------------------------------------------------------
                    when S_PREDICT =>
                        if fruits(i_idx).active = '1' then
                            -- Snapshot (used by DERIVE_VEL at end of frame)
                            x_prev(i_idx) <= fruits(i_idx).x;
                            y_prev(i_idx) <= fruits(i_idx).y;

                            -- Gravity accumulation (clamped to terminal velocity)
                            vy_eff := fruits(i_idx).vy + GRAVITY_FP;
                            if vy_eff > VMAX_FP then vy_eff := VMAX_FP; end if;

                            -- Euler position prediction
                            fruits(i_idx).x  <= fruits(i_idx).x + fruits(i_idx).vx;
                            fruits(i_idx).y  <= fruits(i_idx).y + vy_eff;

                            -- Store gravity-augmented vy for reference
                            -- (DERIVE_VEL will overwrite it with the displacement)
                            fruits(i_idx).vy <= vy_eff;

                            -- Grace countdown
                            if grace_cnt(i_idx) /= 0 then
                                grace_cnt(i_idx) <= grace_cnt(i_idx) - 1;
                            end if;
                        end if;

                        if i_idx = MAX_FRUITS-1 then
                            state <= S_WALLS;
                            i_idx <= 0;
                        else
                            i_idx <= i_idx + 1;
                        end if;

                    ----------------------------------------------------------
                    -- PBD STEP 2a: Wall / floor constraints.
                    -- Position-only: clamp x/y into the play area.
                    -- Setting prev_pos = clamped_pos makes DERIVE_VEL give
                    -- zero velocity on the contact axis (perfectly inelastic).
                    ----------------------------------------------------------
                    when S_WALLS =>
                        if fruits(i_idx).active = '1' then
                            r_i      := FRUIT_RADIUS(to_integer(fruits(i_idx).ftype));
                            fr_left  := to_fp(PLAY_LEFT  + r_i);
                            fr_right := to_fp(PLAY_RIGHT - r_i);
                            fr_bot   := to_fp(PLAY_BOT   - r_i);

                            -- Left wall
                            if fruits(i_idx).x < fr_left then
                                fruits(i_idx).x <= fr_left;
                                x_prev(i_idx)   <= fr_left;   -- zero vx after derive
                            end if;
                            -- Right wall
                            if fruits(i_idx).x > fr_right then
                                fruits(i_idx).x <= fr_right;
                                x_prev(i_idx)   <= fr_right;
                            end if;
                            -- Floor
                            if fruits(i_idx).y > fr_bot then
                                fruits(i_idx).y <= fr_bot;
                                y_prev(i_idx)   <= fr_bot;    -- zero vy after derive
                            end if;
                        end if;

                        if i_idx = MAX_FRUITS-1 then
                            state <= S_COL_OUTER;
                            i_idx <= 0;
                        else
                            i_idx <= i_idx + 1;
                        end if;

                    ----------------------------------------------------------
                    -- PBD STEP 2b: Pairwise collision constraints.
                    ----------------------------------------------------------
                    when S_COL_OUTER =>
                        if i_idx >= MAX_FRUITS-1 then
                            state <= S_DONE;
                        elsif fruits(i_idx).active = '1' then
                            j_idx <= i_idx + 1;
                            state <= S_COL_INNER_LOAD;
                        else
                            i_idx <= i_idx + 1;
                        end if;

                    when S_COL_INNER_LOAD =>
                        state <= S_COL_CHECK;  -- pipeline break before the multiply

                    when S_COL_CHECK =>
                        if fruits(j_idx).active = '1' then
                            -- Compute in Q12.4 units (pixels * 16) throughout so
                            -- the distance and radii are on the same scale.
                            dx_i     := to_integer(fruits(j_idx).x)
                                      - to_integer(fruits(i_idx).x);
                            dy_i     := to_integer(fruits(j_idx).y)
                                      - to_integer(fruits(i_idx).y);
                            r_i      := FRUIT_RADIUS(to_integer(fruits(i_idx).ftype)) * 16;
                            r_j      := FRUIT_RADIUS(to_integer(fruits(j_idx).ftype)) * 16;
                            r_sum    := r_i + r_j;
                            r_sum_sq := r_sum * r_sum;
                            dist_sq  := dx_i*dx_i + dy_i*dy_i;

                            if dist_sq < r_sum_sq then
                                pair_dx    <= to_signed(dx_i, 17);
                                pair_dy    <= to_signed(dy_i, 17);
                                pair_r_sum <= r_sum;
                                state      <= S_COL_RESPOND;
                            else
                                if j_idx = MAX_FRUITS-1 then
                                    i_idx <= i_idx + 1;
                                    state <= S_COL_OUTER;
                                else
                                    j_idx <= j_idx + 1;
                                    state <= S_COL_INNER_LOAD;
                                end if;
                            end if;
                        else
                            if j_idx = MAX_FRUITS-1 then
                                i_idx <= i_idx + 1;
                                state <= S_COL_OUTER;
                            else
                                j_idx <= j_idx + 1;
                                state <= S_COL_INNER_LOAD;
                            end if;
                        end if;

                    ----------------------------------------------------------
                    when S_COL_RESPOND =>
                        if fruits(i_idx).ftype = fruits(j_idx).ftype
                           and to_integer(fruits(i_idx).ftype) < NUM_TYPES-1 then

                            -- Same type: queue a merge
                            merge_x       <= shift_right(
                                fruits(i_idx).x + fruits(j_idx).x, 1);
                            merge_y       <= shift_right(
                                fruits(i_idx).y + fruits(j_idx).y, 1);
                            merge_type    <= fruits(i_idx).ftype + 1;
                            merge_pending <= '1';
                            fruits(i_idx).active <= '0';
                            fruits(j_idx).active <= '0';
                            grace_cnt(i_idx) <= (others => '0');
                            grace_cnt(j_idx) <= (others => '0');
                            state <= S_COL_MERGE;

                        else
                            -------------------------------------------------------
                            -- PBD positional correction.
                            -- *** NO VELOCITY CHANGES HERE. ***
                            --
                            -- Push i and j apart by half the penetration depth
                            -- along the contact normal.  prev_pos is intentionally
                            -- left unchanged so that DERIVE_VEL encodes the
                            -- separation as a repulsive velocity automatically.
                            -------------------------------------------------------
                            abs_dx_v := abs(to_integer(pair_dx));
                            abs_dy_v := abs(to_integer(pair_dy));

                            -- Octagon distance approximation (no sqrt required)
                            if abs_dx_v >= abs_dy_v then
                                dist_approx := abs_dx_v + abs_dy_v / 4;
                            else
                                dist_approx := abs_dy_v + abs_dx_v / 4;
                            end if;
                            if dist_approx < 8 then dist_approx := 8; end if;

                            penetration := pair_r_sum - dist_approx;

                            if penetration > 0 then
                                -- correction = (dx,dy) * penetration / (dist * 2)
                                px := (to_integer(pair_dx) * penetration)
                                      / (dist_approx * 2);
                                py := (to_integer(pair_dy) * penetration)
                                      / (dist_approx * 2);

                                -- Safety clamp (deep overlaps on first frame after merge)
                                if px >  16 then px :=  16; end if;
                                if px < -16 then px := -16; end if;
                                if py >  16 then py :=  16; end if;
                                if py < -16 then py := -16; end if;

                                fruits(i_idx).x <= fruits(i_idx).x - to_signed(px, 16);
                                fruits(i_idx).y <= fruits(i_idx).y - to_signed(py, 16);
                                fruits(j_idx).x <= fruits(j_idx).x + to_signed(px, 16);
                                fruits(j_idx).y <= fruits(j_idx).y + to_signed(py, 16);

                                -- 2. Reset prev_pos to corrected pos so velocity
                                --    derived from this collision = 0.
                                --    In VHDL all signal reads in one process cycle
                                --    see the pre-update value, so
                                --    "fruits(i_idx).x - to_signed(px,16)" reads
                                --    the CURRENT x before the correction above takes
                                --    effect, correctly computing the same target.
                                x_prev(i_idx) <= fruits(i_idx).x - to_signed(px, 16);
                                y_prev(i_idx) <= fruits(i_idx).y - to_signed(py, 16);
                                x_prev(j_idx) <= fruits(j_idx).x + to_signed(px, 16);
                                y_prev(j_idx) <= fruits(j_idx).y + to_signed(py, 16);

                            end if;

                            if j_idx = MAX_FRUITS-1 then
                                i_idx <= i_idx + 1;
                                state <= S_COL_OUTER;
                            else
                                j_idx <= j_idx + 1;
                                state <= S_COL_INNER_LOAD;
                            end if;
                        end if;

                    ----------------------------------------------------------
                    when S_COL_MERGE =>
                        placed := false;
                        for k in 0 to MAX_FRUITS-1 loop
                            if not placed and fruits(k).active = '0' then
                                fruits(k).active <= '1';
                                fruits(k).ftype  <= merge_type;
                                fruits(k).x      <= merge_x;
                                fruits(k).y      <= merge_y;
                                fruits(k).vx     <= (others => '0');
                                fruits(k).vy     <= (others => '0');
                                -- Initialise prev = current so first-frame velocity = 0.
                                -- The new fruit's weight will drive it into the pile over
                                -- subsequent frames naturally.
                                x_prev(k) <= merge_x;
                                y_prev(k) <= merge_y;
                                -- grace = 0: merged fruit is already inside play area
                                grace_cnt(k) <= (others => '0');
                                placed := true;
                            end if;
                        end loop;
                        merge_pending <= '0';

                        score_pulse_r <= '1';
                        score_value_r <= to_unsigned(
                            MERGE_SCORE(to_integer(merge_type)), 8);

                        if j_idx = MAX_FRUITS-1 then
                            i_idx <= i_idx + 1;
                            state <= S_COL_OUTER;
                        else
                            j_idx <= j_idx + 1;
                            state <= S_COL_INNER_LOAD;
                        end if;
                    
                    ----------------------------------------------------------
                    -- Iteration gate.
                    -- Run another full pass of (S_WALLS -> S_COL_*) until
                    -- MAX_ITER total passes, then derive velocities.
                    -- More passes resolve deeper overlaps but cost more cycles.
                    ----------------------------------------------------------
                    when S_DONE =>
                        if col_iter < MAX_ITER then
                            col_iter <= col_iter + 1;
                            i_idx    <= 0;
                            state    <= S_WALLS;
                        else
                            col_iter <= 0;
                            i_idx    <= 0;
                            state    <= S_DERIVE_VEL;
                        end if;

                    ----------------------------------------------------------
                    -- PBD STEP 3: Derive velocity from displacement.
                    --
                    --   vx = current_x - x_prev   (wall contact -> x_prev = x -> vx = 0)
                    --   vy = current_y - y_prev   (floor contact -> y_prev = y -> vy = 0)
                    --
                    -- Apply mild horizontal damping to bleed lateral kinetic
                    -- energy (simulates rolling/friction).  No vertical damping
                    -- is needed: gravity re-accelerates falling fruits each frame,
                    -- and the floor constraint already zeroes vy on landing.
                    ----------------------------------------------------------
                    when S_DERIVE_VEL =>
                        if fruits(i_idx).active = '1' then
                            new_vx := fruits(i_idx).x - x_prev(i_idx);
                            new_vy := fruits(i_idx).y - y_prev(i_idx);

                            -- Horizontal air drag / rolling friction
                            new_vx := fp_damp_15_16(new_vx);
                            
                            if new_vy < 0 then new_vy := shift_right(new_vy, 4); end if;
                            
                            -- 2. VELOCITY DEADZONE (SLEEP)
                            -- Kills lateral micro-sliding
                            if abs(to_integer(new_vx)) < 3 then
                                new_vx := (others => '0');
                            end if;

                            -- ONLY deadzone upward bounces. 
                            -- If we deadzone positive vy, we eat gravity before it accumulates!
                            if new_vy < 0 and abs(to_integer(new_vy)) < 3 then
                                new_vy := (others => '0');
                            end if;
    
                            
                            -- Clamp to terminal velocity
                            if new_vx >  VMAX_FP then new_vx :=  VMAX_FP; end if;
                            if new_vx < -VMAX_FP then new_vx := -VMAX_FP; end if;
                            if new_vy >  VMAX_FP then new_vy :=  VMAX_FP; end if;
                            if new_vy < -VMAX_FP then new_vy := -VMAX_FP; end if;

                            fruits(i_idx).vx <= new_vx;
                            fruits(i_idx).vy <= new_vy;
                        end if;

                        if i_idx = MAX_FRUITS-1 then
                            state <= S_GAMEOVER_CHK;
                            i_idx <= 0;
                        else
                            i_idx <= i_idx + 1;
                        end if;

                    ----------------------------------------------------------
                    when S_GAMEOVER_CHK =>
                        -- With PBD, fruits settle fast and vy stays near 0 when
                        -- stacked.  The grace guard prevents a freshly dropped
                        -- fruit triggering game over before entering the jar.
                        if fruits(i_idx).active = '1'
                           and grace_cnt(i_idx) = 0 then
                            r_i := FRUIT_RADIUS(to_integer(fruits(i_idx).ftype));
                            if fp_to_int(fruits(i_idx).y) - r_i < GAMEOVER_LINE
                               and fp_to_int(fruits(i_idx).vy) >= 0 then
                                gameover_reg <= '1';
                            end if;
                        end if;

                        if i_idx = MAX_FRUITS-1 then
                            state <= S_IDLE;
                            i_idx <= 0;
                        else
                            i_idx <= i_idx + 1;
                        end if;

                    ----------------------------------------------------------
                    when S_SPAWN_SCAN =>
                        placed := false;
                        for k in 0 to MAX_FRUITS-1 loop
                            if not placed and fruits(k).active = '0' then
                                fruits(k).active <= '1';
                                fruits(k).ftype  <= spawn_t_lat;
                                fruits(k).x      <= to_fp(to_integer(spawn_x_lat));
                                fruits(k).y      <= to_fp(PLAY_TOP - 20);
                                fruits(k).vx     <= (others => '0');
                                fruits(k).vy     <= (others => '0');
                                -- prev = current so initial derived velocity = 0.
                                -- Gravity will start pulling it down from the next frame.
                                x_prev(k) <= to_fp(to_integer(spawn_x_lat));
                                y_prev(k) <= to_fp(PLAY_TOP - 20);
                                -- Grace gives this fruit time to fall into the jar
                                -- before it can contribute to a game-over check.
                                grace_cnt(k) <= to_unsigned(GRACE_FRAMES, 7);
                                placed := true;
                            end if;
                        end loop;
                        spawn_latched <= '0';
                        state <= S_IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture;
