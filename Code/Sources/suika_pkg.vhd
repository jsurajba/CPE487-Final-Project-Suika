--==============================================================================
-- suika_pkg.vhd  
-- Shared types, constants, and helper functions for the Suika game.
--
-- Target: Nexys A7-100T, 800x600 @ 60 Hz, 40 MHz pixel clock
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package suika_pkg is

    ----------------------------------------------------------------------------
    -- Display geometry (matches vga_sync.vhd: 800x600 active)
    ----------------------------------------------------------------------------
    constant SCREEN_W   : integer := 800;
    constant SCREEN_H   : integer := 600;

    -- Play area ("the jar"): 300 wide x 530 tall, centered horizontally
    constant PLAY_LEFT  : integer := 250;
    constant PLAY_RIGHT : integer := 550;
    constant PLAY_TOP   : integer := 150;
    constant PLAY_BOT   : integer := 450;

    -- Game-over line
    constant GAMEOVER_LINE : integer := 180;

    ----------------------------------------------------------------------------
    -- Game parameters
    ----------------------------------------------------------------------------
    constant MAX_FRUITS : integer := 28;   -- <<< OPTIMIZED (was 50)
    constant NUM_TYPES  : integer := 11;   -- cherry .. watermelon
    constant DROP_TYPES : integer := 5;    -- only the smallest 5 can spawn

    ----------------------------------------------------------------------------
    -- Fixed-point arithmetic (Q12.4 signed)
    ----------------------------------------------------------------------------
    constant FP_FRAC : integer := 4;
    subtype  fixed_t is signed(15 downto 0);

    function to_fp(i : integer) return fixed_t;     -- int -> Q12.4
    function fp_to_int(f : fixed_t) return integer; -- Q12.4 -> int (truncate)

    ----------------------------------------------------------------------------
    -- Physics constants (Q12.4 unless noted)
    ----------------------------------------------------------------------------
    constant GRAVITY_FP : fixed_t := to_signed(2, 16);   -- 0.125 px/frame^2
    constant VMAX_FP    : fixed_t := to_signed(12*16, 16); -- 12 px/frame cap

    -- Collision separation push (higher = softer/squishier)
    constant SEP_SHIFT  : integer := 1;   -- try 4 for even softer stacking

    ----------------------------------------------------------------------------
    -- Fruit record. Position and velocity are Q12.4.
    ----------------------------------------------------------------------------
    type fruit_t is record
        active : std_logic;
        ftype  : unsigned(3 downto 0);  -- 0..10
        x      : fixed_t;
        y      : fixed_t;
        vx     : fixed_t;
        vy     : fixed_t;
    end record;

    constant FRUIT_NULL : fruit_t := (
        active => '0',
        ftype  => (others => '0'),
        x      => (others => '0'),
        y      => (others => '0'),
        vx     => (others => '0'),
        vy     => (others => '0')
    );

    type fruit_array_t is array (0 to MAX_FRUITS-1) of fruit_t;

    ----------------------------------------------------------------------------
    -- Per-type radii (integer pixels)
    ----------------------------------------------------------------------------
    type radius_array_t is array (0 to NUM_TYPES-1) of integer;
    constant FRUIT_RADIUS : radius_array_t :=
        (8, 12, 16, 20, 24, 28, 32, 38, 44, 52, 60);

    ----------------------------------------------------------------------------
    -- Per-type colors (12-bit RGB: RRRR GGGG BBBB)
    ----------------------------------------------------------------------------
    type color_array_t is array (0 to NUM_TYPES-1)
        of std_logic_vector(11 downto 0);
    constant FRUIT_COLOR : color_array_t := (
        x"F22",  -- cherry
        x"F88",  -- strawberry
        x"82F",  -- grape
        x"FA0",  -- dekopon
        x"F60",  -- persimmon
        x"F44",  -- apple
        x"DC8",  -- pear
        x"FBC",  -- peach
        x"FE4",  -- pineapple
        x"4F4",  -- melon
        x"2A4"   -- watermelon
    );

    constant BG_COLOR    : std_logic_vector(11 downto 0) := x"123";
    constant WALL_COLOR  : std_logic_vector(11 downto 0) := x"FFF";
    constant LINE_COLOR  : std_logic_vector(11 downto 0) := x"F44";
    constant PREVIEW_COL : std_logic_vector(11 downto 0) := x"AAA";

    ----------------------------------------------------------------------------
    -- Score table indexed by *resulting* fruit type after a merge
    ----------------------------------------------------------------------------
    type score_array_t is array (0 to NUM_TYPES-1) of integer;
    constant MERGE_SCORE : score_array_t :=
        (0, 1, 3, 6, 10, 15, 21, 28, 36, 45, 55);

    ----------------------------------------------------------------------------
    -- Helper functions on fixed_t
    ----------------------------------------------------------------------------
    function fp_damp_15_16(v : fixed_t) return fixed_t;  -- v * 15/16
    function fp_damp_3_4  (v : fixed_t) return fixed_t;  -- v * 3/4
    function fp_damp_1_2  (v : fixed_t) return fixed_t;  -- v * 1/2

end package suika_pkg;


package body suika_pkg is

    function to_fp(i : integer) return fixed_t is
    begin
        return to_signed(i * 16, 16);
    end function;

    function fp_to_int(f : fixed_t) return integer is
    begin
        return to_integer(shift_right(f, FP_FRAC));
    end function;

    function fp_damp_15_16(v : fixed_t) return fixed_t is
    begin
        return v - shift_right(v, 4);
    end function;

    function fp_damp_3_4(v : fixed_t) return fixed_t is
    begin
        return v - shift_right(v, 2);
    end function;

    function fp_damp_1_2(v : fixed_t) return fixed_t is
    begin
        return shift_right(v, 1);
    end function;

end package body suika_pkg;