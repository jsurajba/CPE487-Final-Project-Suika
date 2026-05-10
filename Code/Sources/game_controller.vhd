--==============================================================================
-- game_controller.vhd
-- Top-level game logic.  Connects buttons, the random fruit picker, and the
-- physics engine.
--
--   * Generates frame_tick from VSYNC falling edge (one pulse per frame)
--   * Tracks drop position (left/right buttons move it, clamped to jar)
--   * On drop button: emits spawn_req to the physics engine and advances
--     to the next fruit type from the LFSR.  Cooldown prevents spam.
--   * Accumulates score_value pulses into a 16-bit running score.
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.suika_pkg.all;

entity game_controller is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;

        -- Button press pulses (1 cycle wide, post-debounce)
        btn_left     : in  std_logic;
        btn_right    : in  std_logic;
        btn_drop     : in  std_logic;
        btn_reset    : in  std_logic;

        -- Held levels for repeat-while-held movement
        lvl_left     : in  std_logic;
        lvl_right    : in  std_logic;

        -- VSYNC from VGA
        vsync        : in  std_logic;

        -- Random next fruit type from LFSR
        rng_next     : in  unsigned(3 downto 0);

        -- From physics engine
        score_pulse  : in  std_logic;
        score_value  : in  unsigned(7 downto 0);
        gameover_in  : in  std_logic;
        spawn_accepted : in std_logic;
        fruit_in_flight : in std_logic;

        -- To physics engine
        frame_tick   : out std_logic;
        spawn_req    : out std_logic;
        spawn_x      : out unsigned(10 downto 0);
        spawn_type   : out unsigned(3 downto 0);
        physics_rst  : out std_logic;

        -- To renderer
        drop_x       : out unsigned(10 downto 0);
        drop_type    : out unsigned(3 downto 0);

        -- Status
        score        : out unsigned(15 downto 0)
    );
end entity;

architecture rtl of game_controller is

    -- VSYNC edge detection
    signal vsync_d1, vsync_d2 : std_logic := '1';
    signal frame_tick_r       : std_logic := '0';

    -- Drop state
    signal drop_x_r    : unsigned(10 downto 0) := to_unsigned(
        (PLAY_LEFT + PLAY_RIGHT) / 2, 11);
    signal drop_type_r : unsigned(3 downto 0)  := (others => '0');

    -- Spawn one-shot
    signal spawn_req_r : std_logic := '0';

    --drop_pending
    signal drop_pending : std_logic := '0';
    signal fruit_in_flight_d : std_logic := '0';

    -- Repeat-while-held: move every N frames
    signal repeat_div  : unsigned(2 downto 0) := (others => '0');
    constant MOVE_STEP : integer := 3;  -- pixels per move

    -- Score accumulator
    signal score_r     : unsigned(15 downto 0) := (others => '0');

    -- Reset request
    signal phys_rst_r  : std_logic := '0';

begin

    frame_tick  <= frame_tick_r;
    spawn_req   <= spawn_req_r;
    spawn_x     <= drop_x_r;
    spawn_type  <= drop_type_r;
    drop_x      <= drop_x_r;
    drop_type   <= drop_type_r;
    score       <= score_r;
    physics_rst <= phys_rst_r;

    --==========================================================================
    -- VSYNC edge detect -> frame_tick
    --==========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            vsync_d1 <= vsync;
            vsync_d2 <= vsync_d1;
            -- Falling edge of vsync = start of sync pulse = start of new frame
            if vsync_d2 = '1' and vsync_d1 = '0' then
                frame_tick_r <= '1';
            else
                frame_tick_r <= '0';
            end if;
        end if;
    end process;

    --==========================================================================
    -- Main control logic
    --==========================================================================
    process(clk)
        variable r_cur : integer;
    begin
        if rising_edge(clk) then
            
            fruit_in_flight_d <= fruit_in_flight;
            spawn_req_r <= '0';
            phys_rst_r  <= '0';

            if rst = '1' then
                drop_x_r    <= to_unsigned((PLAY_LEFT + PLAY_RIGHT)/2, 11);
                drop_type_r <= (others => '0');
                drop_pending <= '0';
                repeat_div  <= (others => '0');
                score_r     <= (others => '0');
                fruit_in_flight_d <= '0';
            else
                ----------------------------------------------------------------
                -- RESET button: clear score, reset physics, reset drop pos
                ----------------------------------------------------------------
                if btn_reset = '1' then
                    drop_x_r    <= to_unsigned((PLAY_LEFT + PLAY_RIGHT)/2, 11);
                    drop_type_r <= rng_next;
                    score_r     <= (others => '0');
                    phys_rst_r  <= '1';
                    drop_pending <= '0';
                end if;

                ----------------------------------------------------------------
                -- Movement: buttons can be tapped or held.
                -- On press pulse: immediate move.
                -- While held: move every few frames.
                ----------------------------------------------------------------
                r_cur := FRUIT_RADIUS(to_integer(drop_type_r));

                if frame_tick_r = '1' then
                    repeat_div <= repeat_div + 1;
                end if;

                -- Pressed (single tap)
                if btn_left = '1' then
                    if to_integer(drop_x_r) > PLAY_LEFT + r_cur + MOVE_STEP then
                        drop_x_r <= drop_x_r - to_unsigned(MOVE_STEP, 11);
                    else
                        drop_x_r <= to_unsigned(PLAY_LEFT + r_cur, 11);
                    end if;
                end if;
                if btn_right = '1' then
                    if to_integer(drop_x_r) + r_cur + MOVE_STEP < PLAY_RIGHT then
                        drop_x_r <= drop_x_r + to_unsigned(MOVE_STEP, 11);
                    else
                        drop_x_r <= to_unsigned(PLAY_RIGHT - r_cur, 11);
                    end if;
                end if;

                -- Held (repeat every 4 frames)
                if frame_tick_r = '1' and repeat_div = "000" then
                    if lvl_left = '1' and lvl_right = '0' then
                        if to_integer(drop_x_r) > PLAY_LEFT + r_cur + MOVE_STEP then
                            drop_x_r <= drop_x_r - to_unsigned(MOVE_STEP, 11);
                        end if;
                    elsif lvl_right = '1' and lvl_left = '0' then
                        if to_integer(drop_x_r) + r_cur + MOVE_STEP < PLAY_RIGHT then
                            drop_x_r <= drop_x_r + to_unsigned(MOVE_STEP, 11);
                        end if;
                    end if;
                end if;

                ----------------------------------------------------------------
                -- DROP button
                ----------------------------------------------------------------
                if btn_drop = '1' and drop_pending = '0' and gameover_in = '0' then
                    spawn_req_r  <= '1';
                    drop_pending <= '1';
                end if;

                -- Advance preview ONLY when physics actually accepted the drop
                -- ADD (decouple the two jobs):
                if spawn_accepted = '1' then
                    drop_type_r <= rng_next;   -- advance preview as before
                end if;
                
                if fruit_in_flight_d = '1' and fruit_in_flight = '0' then
                    drop_pending <= '0';
                end if;

                ----------------------------------------------------------------
                -- SCORE accumulation
                ----------------------------------------------------------------
                if score_pulse = '1' then
                    score_r <= score_r + resize(score_value, 16);
                end if;
            end if;
        end if;
    end process;

end architecture;
