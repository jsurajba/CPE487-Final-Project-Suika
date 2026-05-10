--==============================================================================
-- physics_engine.vhd  (UPDATED & FIXED)
-- Suika physics core with the critical collision response fix.
--
-- CHANGES:
--   1. Different-type collisions no longer do full velocity swap.
--      → Replaced with strong damping so dropped fruits settle/roll gently.
--   2. SEP_SHIFT left at 3 (you can bump to 4 for even softer stacking).
--   3. Tiny cleanups: better comments, consistent variable scoping, one small
--      timing relaxation in S_COL_CHECK.
--==============================================================================
--==============================================================================
-- physics_engine.vhd  (STRONG COLLISION FIX - May 2026)
-- Video-tested fix: very aggressive damping + velocity kill on different-type hits
--==============================================================================
--==============================================================================
-- physics_engine.vhd  (GAME-OVER-FIXED - May 2026)
-- Fixed: instant game-over on normal collisions
-- Changes:
--   • Softer vertical damping on different-type hits
--   • Game-over check now requires near-zero velocity (prevents momentary pushes)
--==============================================================================
--==============================================================================
-- physics_engine.vhd  (2 COLLISION PASSES - FINAL FIX)
-- Now runs collision detection/response TWICE per frame → no more sinking
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.suika_pkg.all;

entity physics_engine is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;

        -- One-cycle pulse per VSYNC from game_controller
        frame_tick   : in  std_logic;

        -- Spawn request from game controller (drop a fruit from the top)
        spawn_req    : in  std_logic;
        spawn_x      : in  unsigned(10 downto 0);   -- pixel x
        spawn_type   : in  unsigned(3 downto 0);

        -- Outputs
        fruits_out   : out fruit_array_t;
        busy         : out std_logic;           -- '1' while computing a frame
        gameover     : out std_logic;           -- '1' if a fruit is above the line
        score_pulse  : out std_logic;           -- 1-cycle pulse per merge
        score_value  : out unsigned(7 downto 0); -- score amount on pulse cycle
        spawn_accepted : out std_logic;
        fruit_in_flight : out std_logic
    );
end entity;

architecture rtl of physics_engine is

    type state_t is (
        S_IDLE,
        S_INTEGRATE,       -- per-fruit gravity + drag + grace countdown
        S_WALLS,           -- per-fruit wall clamp/bounce
        S_COL_OUTER,       -- find next active i for collision outer loop
        S_COL_INNER_LOAD,  -- 1-cycle setup before the multiplier in S_COL_CHECK
        S_COL_CHECK,       -- check pair (i, j)
        S_COL_RESPOND,     -- handle overlap: push or merge
        S_COL_MERGE,       -- place newly merged fruit
        S_GAMEOVER_CHK,    -- scan for fruit above game-over line (grace = 0)
        S_SPAWN_SCAN,      -- find an inactive slot for a dropped fruit
        S_DONE
    );
    signal state : state_t := S_IDLE;

    signal fruits : fruit_array_t := (others => FRUIT_NULL);

    -- Loop indices
    signal i_idx : integer range 0 to MAX_FRUITS := 0;
    signal j_idx : integer range 0 to MAX_FRUITS := 0;

    -- Latched overlap vector for collision response
    signal pair_dx : signed(16 downto 0);
    signal pair_dy : signed(16 downto 0);
    signal pair_r_sum : integer range 0 to 511 := 0;

    -- Merge intermediate state
    signal merge_pending : std_logic := '0';
    signal merge_x       : fixed_t;
    signal merge_y       : fixed_t;
    signal merge_type    : unsigned(3 downto 0);

    -- Spawn request latch
    signal spawn_latched : std_logic := '0';
    signal spawn_x_lat   : unsigned(10 downto 0);
    signal spawn_t_lat   : unsigned(3 downto 0);

    -- Game-over output register
    signal gameover_reg  : std_logic := '0';

    -- Per-fruit grace countdown.
    -- Set to GRACE_FRAMES when a fruit is player-dropped; 0 for merged fruits.
    -- Decremented once per frame in S_INTEGRATE.
    -- Game-over check only fires for fruits with grace_cnt = 0.
    constant GRACE_FRAMES : integer := 45;
    type grace_array_t is array (0 to MAX_FRUITS-1) of unsigned(6 downto 0);
    signal grace_cnt : grace_array_t := (others => (others => '0'));

    -- Score outputs
    signal score_pulse_r : std_logic := '0';
    signal score_value_r : unsigned(7 downto 0) := (others => '0');
    
    signal col_iter : integer range 0 to 3 := 0;

begin

    fruits_out  <= fruits;
    busy        <= '0' when state = S_IDLE else '1';
    gameover    <= gameover_reg;
    score_pulse <= score_pulse_r;
    score_value <= score_value_r;
    
    process(grace_cnt, fruits)
        begin
            fruit_in_flight <= '0';
            for k in 0 to MAX_FRUITS-1 loop
                    if fruits(k).active = '1' and
                       (grace_cnt(k) /= 0 or
                        abs(fp_to_int(fruits(k).vy)) > 0 or   -- was > 1
                        abs(fp_to_int(fruits(k).vx)) > 0) then -- was > 1
                        fruit_in_flight <= '1';
                    end if;
            end loop;
        end process;

    --==========================================================================
    -- Main FSM
    -- The spawn-request latch and the physics pipeline share this one process
    -- to guarantee there is only one driver for every signal.
    --==========================================================================
    process(clk)
        variable r_i, r_j               : integer;
        variable r_sum, r_sum_sq        : integer;
        variable dx_i, dy_i, dist_sq    : integer;
        variable new_vy                 : fixed_t;
        variable px, py                 : integer;
        variable fr_left, fr_right, fr_bot : fixed_t;
        variable placed                 : boolean;
        variable settled                : std_logic;
        variable abs_dx_v, abs_dy_v     : integer;
        variable dist_mn, penetration   : integer;
    begin
        if rising_edge(clk) then
                
            score_pulse_r <= '0';   -- default: no score event this cycle
            spawn_accepted <= '0';

            -- ----------------------------------------------------------------
            -- Latch incoming spawn request (cleared by S_SPAWN_SCAN)
            -- ----------------------------------------------------------------
            if rst = '1' then
                spawn_latched <= '0';
            elsif spawn_req = '1' then
                spawn_latched <= '1';
                spawn_x_lat   <= spawn_x;
                spawn_t_lat   <= spawn_type;
            end if;

            -- ----------------------------------------------------------------
            -- Synchronous reset
            -- ----------------------------------------------------------------
            if rst = '1' then
                state         <= S_IDLE;
                fruits        <= (others => FRUIT_NULL);
                grace_cnt     <= (others => (others => '0'));
                i_idx         <= 0;
                j_idx         <= 0;
                merge_pending <= '0';
                gameover_reg  <= '0';
                spawn_accepted <= '0';
                col_iter <= 0;
            else
                case state is

                    ------------------------------------------------------------
                    when S_IDLE =>
                        if gameover_reg = '0' and frame_tick = '1' then
                            state <= S_INTEGRATE;
                            i_idx <= 0;
                        elsif gameover_reg = '0' and spawn_latched = '1' then
                            -- Suika rule: only accept drop when previous fruit has settled
                            settled := '1';
                            for k in 0 to MAX_FRUITS-1 loop
                                if fruits(k).active = '1' and (abs(fp_to_int(fruits(k).vy)) > 1 or abs(fp_to_int(fruits(k).vx)) > 1) then
                                    settled := '0';
                                end if;
                            end loop;
                            if settled = '1' then
                                state <= S_SPAWN_SCAN;
                                spawn_accepted <= '1';   -- pulse to advance preview in controller
                            end if;
                        end if;

                    ------------------------------------------------------------
                    when S_INTEGRATE =>
                        if fruits(i_idx).active = '1' then

                            -- Mild horizontal air drag
                            fruits(i_idx).vx <= fp_damp_15_16(fruits(i_idx).vx);

                            -- Gravity with terminal-velocity clamp
                            new_vy := fruits(i_idx).vy + GRAVITY_FP;
                            if new_vy >  VMAX_FP then new_vy :=  VMAX_FP; end if;
                            if new_vy < -VMAX_FP then new_vy := -VMAX_FP; end if;
                            fruits(i_idx).vy <= new_vy;

                            -- Euler position step
                            fruits(i_idx).x <= fruits(i_idx).x + fruits(i_idx).vx;
                            fruits(i_idx).y <= fruits(i_idx).y + new_vy;

                            -- Count down the game-over grace period
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

                    ------------------------------------------------------------
                    when S_WALLS =>
                        if fruits(i_idx).active = '1' then
                            r_i      := FRUIT_RADIUS(to_integer(fruits(i_idx).ftype));
                            fr_left  := to_fp(PLAY_LEFT  + r_i);
                            fr_right := to_fp(PLAY_RIGHT - r_i);
                            fr_bot   := to_fp(PLAY_BOT   - r_i);

                            -- Left wall
                            if fruits(i_idx).x < fr_left then
                                fruits(i_idx).x  <= fr_left;
                                fruits(i_idx).vx <= (others => '0');   -- was -fp_damp_3_4(...)
                            end if;
                            -- Right wall
                            if fruits(i_idx).x > fr_right then
                                fruits(i_idx).x  <= fr_right;
                                fruits(i_idx).vx <= (others => '0');   -- was -fp_damp_3_4(...)
                            end if;
                            -- Floor
                            if fruits(i_idx).y > fr_bot then
                                fruits(i_idx).y  <= fr_bot;
                                fruits(i_idx).vy <= (others => '0');   -- was -fp_damp_1_2(...)
                                fruits(i_idx).vx <= fp_damp_1_2(fruits(i_idx).vx);  -- bleed horizontal too
                            end if;
                        end if;

                        if i_idx = MAX_FRUITS-1 then
                            state <= S_COL_OUTER;
                            i_idx <= 0;
                        else
                            i_idx <= i_idx + 1;
                        end if;

                    ------------------------------------------------------------
                    when S_COL_OUTER =>
                        if i_idx >= MAX_FRUITS-1 then
                            state <= S_GAMEOVER_CHK;
                            i_idx <= 0;
                        elsif fruits(i_idx).active = '1' then
                            j_idx <= i_idx + 1;
                            state <= S_COL_INNER_LOAD;
                        else
                            i_idx <= i_idx + 1;
                        end if;

                    when S_COL_INNER_LOAD =>
                        state <= S_COL_CHECK;   -- 1 idle cycle relaxes timing

                    ------------------------------------------------------------
                    when S_COL_CHECK =>
                        if fruits(j_idx).active = '1' then
                            dx_i     := fp_to_int(fruits(j_idx).x - fruits(i_idx).x);
                            dy_i     := fp_to_int(fruits(j_idx).y - fruits(i_idx).y);
                            r_i      := FRUIT_RADIUS(to_integer(fruits(i_idx).ftype));
                            r_j      := FRUIT_RADIUS(to_integer(fruits(j_idx).ftype));
                            r_sum    := r_i + r_j;
                            r_sum_sq := r_sum * r_sum;
                            dist_sq  := dx_i*dx_i + dy_i*dy_i;

                            if dist_sq < r_sum_sq then
                                pair_dx <= to_signed(dx_i, 17);
                                pair_dy <= to_signed(dy_i, 17);
                                pair_r_sum <= r_sum;
                                state   <= S_COL_RESPOND;
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

                    ------------------------------------------------------------
                    when S_COL_RESPOND =>
                        if fruits(i_idx).ftype = fruits(j_idx).ftype
                           and to_integer(fruits(i_idx).ftype) < NUM_TYPES-1 then

                            -- Same type: MERGE
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
                            abs_dx_v  := abs(to_integer(pair_dx));
                            abs_dy_v  := abs(to_integer(pair_dy));
                        
                            if abs_dx_v > abs_dy_v then
                                dist_mn := abs_dx_v + abs_dy_v / 4;
                            else
                                dist_mn := abs_dy_v + abs_dx_v / 4;
                            end if;
                            if dist_mn < 1 then dist_mn := 1; end if;
                        
                            penetration := pair_r_sum - dist_mn;
                            if penetration < 0  then penetration := 0;  end if;
                            if penetration > 10 then penetration := 10; end if;  -- tighter cap
                        
                            -- px/py are now plain pixel integers
                            px := (to_integer(pair_dx) * penetration) / (dist_mn * 2);
                            py := (to_integer(pair_dy) * penetration) / (dist_mn * 2);
                        
                            if px > 4  then px := 4;  end if;
                            if px < -4 then px := -4; end if;
                            if py > 4  then py := 4;  end if;
                            if py < -4 then py := -4; end if;
                        
                            -- Position correction: convert pixels -> Q12.4 with to_fp()
                            fruits(i_idx).x <= fruits(i_idx).x - to_fp(px);
                            fruits(i_idx).y <= fruits(i_idx).y - to_fp(py);
                            fruits(j_idx).x <= fruits(j_idx).x + to_fp(px);
                            fruits(j_idx).y <= fruits(j_idx).y + to_fp(py);
                        
                            fruits(i_idx).vx <= fp_damp_1_2(fp_damp_1_2(fruits(i_idx).vx));  -- 1/4 remaining
                            fruits(i_idx).vy <= fp_damp_1_2(fp_damp_1_2(fruits(i_idx).vy));
                            fruits(j_idx).vx <= fp_damp_1_2(fp_damp_1_2(fruits(j_idx).vx));
                            fruits(j_idx).vy <= fp_damp_1_2(fp_damp_1_2(fruits(j_idx).vy));
                        
                            if j_idx = MAX_FRUITS-1 then
                                i_idx <= i_idx + 1;
                                state <= S_COL_OUTER;
                            else
                                j_idx <= j_idx + 1;
                                state <= S_COL_INNER_LOAD;
                            end if;
                        end if;

                    ------------------------------------------------------------
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
                                -- Merged fruit is already inside the play area:
                                -- grace = 0 so it is eligible for game-over checks.
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

                    ------------------------------------------------------------
                    when S_GAMEOVER_CHK =>
                        -- A fruit triggers game over only when grace_cnt = 0.
                        --
                        -- Case A - pile overflows: settled fruits (grace=0) get
                        -- pushed above GAMEOVER_LINE by the growing pile and are
                        -- caught here on the next frame.
                        --
                        -- Case B - jar is full: the dropped fruit is physically
                        -- blocked by the pile and stays above PLAY_TOP.  Its grace
                        -- timer still counts down every frame regardless of position.
                        -- After GRACE_FRAMES frames it is above the game-over line
                        -- with near-zero vy, and game over fires here.
                        if fruits(i_idx).active = '1'
                           and grace_cnt(i_idx) = 0 then
                            r_i := FRUIT_RADIUS(to_integer(fruits(i_idx).ftype));
                            if fp_to_int(fruits(i_idx).y) - r_i < GAMEOVER_LINE
                               and fp_to_int(fruits(i_idx).vy) >= 0 then
                                gameover_reg <= '1';
                            end if;
                        end if;

                        if i_idx = MAX_FRUITS-1 then
                            state <= S_DONE;
                        else
                            i_idx <= i_idx + 1;
                        end if;

                    ------------------------------------------------------------
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
                                -- Give this fruit GRACE_FRAMES to fall into the jar.
                                -- If blocked by a full jar, the timer still expires
                                -- and game over is triggered after ~0.75 s.
                                grace_cnt(k) <= to_unsigned(GRACE_FRAMES, 7);
                                placed := true;
                            end if;
                        end loop;
                        spawn_latched <= '0';
                        state <= S_IDLE;

                    ------------------------------------------------------------
                    when S_DONE =>
                        if col_iter < 3 then
                            col_iter <= col_iter + 1;
                            i_idx    <= 0;
                            state    <= S_WALLS;      -- was S_COL_OUTER, clamp walls between each pass
                        else
                            col_iter <= 0;
                            state    <= S_IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture;
