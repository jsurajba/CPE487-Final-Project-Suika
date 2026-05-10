--==============================================================================
-- suika_top.vhd
-- Top-level entity for the Nexys A7-100T.
--
-- I/O mapping (matches the constraints in nexys_a7.xdc):
--   clk_100   : W5  (100 MHz oscillator)
--   btn[0]    : N17 (BTNC) - reset / new game
--   btn[1]    : M18 (BTNU) - drop fruit
--   btn[2]    : P17 (BTNL) - move drop position left
--   btn[3]    : M17 (BTNR) - move drop position right
--   sw[0]     : J15       - master enable (must be high to play)
--   vga_*     : standard Pmod-style VGA on the on-board connector
--   seg, an   : 7-segment display (score)
--   leds      : 16 LEDs (low byte = score lo)
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.suika_pkg.all;

entity suika_top is
    port (
        clk_100   : in  std_logic;
        btn       : in  std_logic_vector(3 downto 0);
        sw        : in  std_logic_vector(0 downto 0);

        -- VGA (4-bit per channel)
        vga_r     : out std_logic_vector(3 downto 0);
        vga_g     : out std_logic_vector(3 downto 0);
        vga_b     : out std_logic_vector(3 downto 0);
        vga_hs    : out std_logic;
        vga_vs    : out std_logic;

        -- 7-segment display
        seg       : out std_logic_vector(6 downto 0);
        dp        : out std_logic;
        an        : out std_logic_vector(7 downto 0);

        -- Status LEDs
        led       : out std_logic_vector(15 downto 0)
    );
end entity;

architecture rtl of suika_top is

    -- Clocks
    signal clk_pix     : std_logic;
    signal mmcm_locked : std_logic;
    signal sys_rst     : std_logic;

    -- VGA
    signal pixel_col   : std_logic_vector(10 downto 0);
    signal pixel_row   : std_logic_vector(10 downto 0);
    signal hsync_int   : std_logic;
    signal vsync_int   : std_logic;

    -- Renderer outputs
    signal r_in, g_in, b_in : std_logic_vector(3 downto 0);

    -- Buttons (debounced)
    signal lvl_reset, lvl_drop, lvl_left, lvl_right : std_logic;
    signal pls_reset, pls_drop, pls_left, pls_right : std_logic;

    -- LFSR
    signal rng_next : unsigned(3 downto 0);

    -- Game controller <-> physics
    signal frame_tick  : std_logic;
    signal spawn_req   : std_logic;
    signal spawn_x     : unsigned(10 downto 0);
    signal spawn_type  : unsigned(3 downto 0);
    signal physics_rst : std_logic;

    -- Physics outputs
    signal fruits      : fruit_array_t;
    signal phys_busy   : std_logic;
    signal phys_go     : std_logic;
    signal sc_pulse    : std_logic;
    signal sc_value    : unsigned(7 downto 0);
    signal sp_acc : std_logic;
    signal fruitfly : std_logic;

    -- Game controller -> renderer
    signal drop_x      : unsigned(10 downto 0);
    signal drop_type   : unsigned(3 downto 0);

    -- Score
    signal score       : unsigned(15 downto 0);

begin

    --==========================================================================
    -- System reset: hold reset until MMCM locks, then run
    --==========================================================================
    sys_rst <= not mmcm_locked or not sw(0);

    --==========================================================================
    -- Clock generation: 100 MHz -> 40 MHz pixel clock
    --==========================================================================
    u_clk : entity work.clock_gen
        port map (
            clk_100 => clk_100,
            rst     => '0',
            clk_pix => clk_pix,
            locked  => mmcm_locked
        );

    --==========================================================================
    -- VGA timing (uses your existing module unchanged)
    --==========================================================================
    u_vga : entity work.vga_sync
        port map (
            pixel_clk => clk_pix,
            red_in    => r_in,
            green_in  => g_in,
            blue_in   => b_in,
            red_out   => vga_r,
            green_out => vga_g,
            blue_out  => vga_b,
            hsync     => hsync_int,
            vsync     => vsync_int,
            pixel_row => pixel_row,
            pixel_col => pixel_col
        );
    vga_hs <= hsync_int;
    vga_vs <= vsync_int;

    --==========================================================================
    -- Button debouncers (4 of them) -- run on pixel clock
    --==========================================================================
    u_db_reset : entity work.debouncer
        generic map (CLK_HZ => 40_000_000, DEBOUNCE_MS => 10)
        port map (clk => clk_pix, rst => '0',
                  btn_in => btn(0), btn_level => lvl_reset, btn_press => pls_reset);

    u_db_drop : entity work.debouncer
        generic map (CLK_HZ => 40_000_000, DEBOUNCE_MS => 10)
        port map (clk => clk_pix, rst => '0',
                  btn_in => btn(1), btn_level => lvl_drop,  btn_press => pls_drop);

    u_db_left : entity work.debouncer
        generic map (CLK_HZ => 40_000_000, DEBOUNCE_MS => 10)
        port map (clk => clk_pix, rst => '0',
                  btn_in => btn(2), btn_level => lvl_left,  btn_press => pls_left);

    u_db_right : entity work.debouncer
        generic map (CLK_HZ => 40_000_000, DEBOUNCE_MS => 10)
        port map (clk => clk_pix, rst => '0',
                  btn_in => btn(3), btn_level => lvl_right, btn_press => pls_right);

    --==========================================================================
    -- LFSR for next-fruit selection
    --==========================================================================
    u_lfsr : entity work.lfsr16
        port map (clk => clk_pix, rst => sys_rst, next_type => rng_next);

    --==========================================================================
    -- Game controller
    --==========================================================================
    u_game : entity work.game_controller
        port map (
            clk         => clk_pix,
            rst         => sys_rst,
            btn_left    => pls_left,
            btn_right   => pls_right,
            btn_drop    => pls_drop,
            btn_reset   => pls_reset,
            lvl_left    => lvl_left,
            lvl_right   => lvl_right,
            vsync       => vsync_int,
            rng_next    => rng_next,
            score_pulse => sc_pulse,
            score_value => sc_value,
            gameover_in => phys_go,
            frame_tick  => frame_tick,
            spawn_req   => spawn_req,
            spawn_x     => spawn_x,
            spawn_type  => spawn_type,
            physics_rst => physics_rst,
            drop_x      => drop_x,
            drop_type   => drop_type,
            score       => score,
            spawn_accepted => sp_acc,
            fruit_in_flight => fruitfly
        );

    --==========================================================================
    -- Physics engine
    --==========================================================================
    u_phys : entity work.physics_engine
        port map (
            clk         => clk_pix,
            rst         => sys_rst or physics_rst,
            frame_tick  => frame_tick,
            spawn_req   => spawn_req,
            spawn_x     => spawn_x,
            spawn_type  => spawn_type,
            fruits_out  => fruits,
            busy        => phys_busy,
            gameover    => phys_go,
            score_pulse => sc_pulse,
            score_value => sc_value,
            spawn_accepted => sp_acc,
            fruit_in_flight => fruitfly
        );

    --==========================================================================
    -- Renderer (combinational pixel -> color)
    --==========================================================================
    u_rndr : entity work.renderer
        port map (
            clk        => clk_pix,
            pixel_col  => pixel_col,
            pixel_row  => pixel_row,
            fruits     => fruits,
            drop_x     => drop_x,
            drop_type  => drop_type,
            gameover   => phys_go,
            red        => r_in,
            green      => g_in,
            blue       => b_in
        );

    --==========================================================================
    -- 7-seg score display (runs on system 100 MHz for refresh smoothness)
    --==========================================================================
    u_seg : entity work.seven_seg
        port map (
            clk   => clk_100,
            rst   => sys_rst,
            value => score,
            seg   => seg,
            dp    => dp,
            an    => an
        );

    --==========================================================================
    -- Status LEDs: lower byte of score; LED15 = gameover; LED14 = busy
    --==========================================================================
    led(7 downto 0)  <= std_logic_vector(score(7 downto 0));
    led(13 downto 8) <= (others => '0');
    led(14)          <= phys_busy;
    led(15)          <= phys_go;

end architecture;
