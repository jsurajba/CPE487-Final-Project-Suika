--==============================================================================
-- renderer.vhd
-- Combinational pixel renderer.  For every pixel coordinate (col, row),
-- decides what color to paint.  Walls, game-over line, and all 50 fruits
-- are evaluated in parallel; the last hit wins (later fruits draw over earlier).
--
-- Squared-distance test:  (px - fx)^2 + (py - fy)^2 <= r^2
-- Inputs in raw pixels (Q12.4 fruit positions are converted to integers here).
--
-- Note on synthesis:
--   This is large combinational logic.  Vivado will infer ~100 small multipliers
--   for 50 fruits.  On the Nexys A7-100T (240 DSP48E1 slices) this fits easily.
--   If post-synthesis timing fails to close at 40 MHz, register the output
--   ('rgb_q' below) by 1-2 stages -- the visual effect is just a few pixels
--   of horizontal shift, which is invisible.
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.suika_pkg.all;

entity renderer is
    port (
        clk         : in  std_logic;          -- pixel clock
        pixel_col   : in  std_logic_vector(10 downto 0);
        pixel_row   : in  std_logic_vector(10 downto 0);
        fruits      : in  fruit_array_t;

        -- Drop indicator (where next fruit will be released)
        drop_x      : in  unsigned(10 downto 0);
        drop_type   : in  unsigned(3 downto 0);
        gameover    : in  std_logic;

        -- VGA color outputs to feed vga_sync
        red         : out std_logic_vector(3 downto 0);
        green       : out std_logic_vector(3 downto 0);
        blue        : out std_logic_vector(3 downto 0)
    );
end entity;

architecture rtl of renderer is
    signal rgb_c : std_logic_vector(11 downto 0);
    signal rgb_q : std_logic_vector(11 downto 0) := (others => '0');
begin

    --==========================================================================
    -- Combinational color decision
    --==========================================================================
    process(pixel_col, pixel_row, fruits, drop_x, drop_type, gameover)
        variable color  : std_logic_vector(11 downto 0);
        variable px, py : integer;
        variable fx, fy : integer;
        variable r      : integer;
        variable dx, dy : integer;
        variable dxn, dyn : integer;
        variable preview_r : integer;
    begin
        px := to_integer(unsigned(pixel_col));
        py := to_integer(unsigned(pixel_row));

        --------------------------------------------------------------------
        -- 1. Background
        --------------------------------------------------------------------
        color := BG_COLOR;

        --------------------------------------------------------------------
        -- 2. Jar walls (left, right, bottom -- 2 pixel thickness)
        --------------------------------------------------------------------
        if py >= PLAY_TOP and py <= PLAY_BOT then
            if (px >= PLAY_LEFT-2  and px <= PLAY_LEFT+1) or
               (px >= PLAY_RIGHT-1 and px <= PLAY_RIGHT+2) then
                color := WALL_COLOR;
            end if;
        end if;
        if (py >= PLAY_BOT-1 and py <= PLAY_BOT+2)
           and (px >= PLAY_LEFT-2 and px <= PLAY_RIGHT+2) then
            color := WALL_COLOR;
        end if;

        --------------------------------------------------------------------
        -- 3. Game-over line (dashed)
        --------------------------------------------------------------------
        if py = GAMEOVER_LINE
           and px >= PLAY_LEFT and px <= PLAY_RIGHT
           and (px / 4) mod 2 = 0 then
            color := LINE_COLOR;
        end if;

        --------------------------------------------------------------------
        -- 4. Drop preview (small circle at top showing next fruit position)
        --------------------------------------------------------------------
        preview_r := FRUIT_RADIUS(to_integer(drop_type));
        dxn := px - to_integer(drop_x);
        dyn := py - (PLAY_TOP - 25);
        if dxn*dxn + dyn*dyn <= preview_r*preview_r then
            color := FRUIT_COLOR(to_integer(drop_type));
        end if;
        -- Vertical aim line
        if px = to_integer(drop_x) and py >= PLAY_TOP and py <= PLAY_TOP+8 then
            color := PREVIEW_COL;
        end if;

        --------------------------------------------------------------------
        -- 5. Active fruits (50 in parallel; later hits overwrite)
        --------------------------------------------------------------------
        for i in 0 to MAX_FRUITS-1 loop
            if fruits(i).active = '1' then
                fx := fp_to_int(fruits(i).x);
                fy := fp_to_int(fruits(i).y);
                r  := FRUIT_RADIUS(to_integer(fruits(i).ftype));
                dx := px - fx;
                dy := py - fy;
                if dx*dx + dy*dy <= r*r then
                    color := FRUIT_COLOR(to_integer(fruits(i).ftype));
                end if;
            end if;
        end loop;

        --------------------------------------------------------------------
        -- 6. Game-over tint: red overlay
        --------------------------------------------------------------------
        if gameover = '1' and ((px + py) mod 8) < 2 then
            color := x"F00";
        end if;

        rgb_c <= color;
    end process;

    --==========================================================================
    -- Register the color once on the pixel clock to ease timing
    --==========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            rgb_q <= rgb_c;
        end if;
    end process;

    red   <= rgb_q(11 downto 8);
    green <= rgb_q(7 downto 4);
    blue  <= rgb_q(3 downto 0);

end architecture;
