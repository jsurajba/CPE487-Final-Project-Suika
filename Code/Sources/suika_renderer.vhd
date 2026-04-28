LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
use work.fruit_pkg.all;

ENTITY suika_renderer IS
    PORT (
        v_sync    : IN STD_LOGIC;
        pixel_row : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
        pixel_col : IN STD_LOGIC_VECTOR(10 DOWNTO 0);
        red       : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        green     : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        blue      : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
    );
END suika_renderer;

ARCHITECTURE Behavioral OF suika_renderer IS
    -- Screen Dimensions
    CONSTANT SCREEN_WIDTH  : INTEGER := 640;
    CONSTANT SCREEN_HEIGHT : INTEGER := 480;

    -- Game Container (The Bucket) Coordinates
    CONSTANT BOX_LEFT   : INTEGER := 180;
    CONSTANT BOX_RIGHT  : INTEGER := 480;
    CONSTANT BOX_BOTTOM : INTEGER := 440;
    CONSTANT BOX_TOP    : INTEGER := 80;
    CONSTANT WALL_THICK : INTEGER := 4;

    -- Test Fruit (Cherry) Properties
    CONSTANT CHERRY_X : INTEGER := 320;
    CONSTANT CHERRY_Y : INTEGER := 350;
    CONSTANT CHERRY_R : INTEGER := 8;
    
    -- Physics Engine
    SIGNAL left : STD_LOGIC;
    SIGNAL right : STD_LOGIC;
    SIGNAL drop : STD_LOGIC;
    SIGNAL all_fruits : STD_LOGIC_VECTOR(19 DOWNTO 0);
    
    COMPONENT physics_engine is
    PORT (
        v_sync    : IN STD_LOGIC;
        -- Buttons for the "Aim" phase
        btnL, btnR, btnDrop : in std_logic;
        -- The output data to the renderer
        all_fruits : out fruit_array
    );
    END COMPONENT;

BEGIN
    process(pixel_row, pixel_col)
        variable r_int, c_int : integer;
        variable dist_sq      : integer;
    begin
        r_int := to_integer(unsigned(pixel_row));
        c_int := to_integer(unsigned(pixel_col));
        
        -- Default Background Color (Dark Blueish-Grey)
        red   <= "0010";
        green <= "0010";
        blue  <= "0011";

        -- Draw the Container Box
        -- Check if current pixel is within the walls or floor
        if (c_int >= BOX_LEFT - WALL_THICK and c_int <= BOX_LEFT) or -- Left Wall
           (c_int >= BOX_RIGHT and c_int <= BOX_RIGHT + WALL_THICK) then -- Right Wall
            if (r_int >= BOX_TOP and r_int <= BOX_BOTTOM) then
                red <= "1111"; green <= "1111"; blue <= "1111"; -- White
            end if;
        elsif (r_int >= BOX_BOTTOM and r_int <= BOX_BOTTOM + WALL_THICK) then -- Floor
            if (c_int >= BOX_LEFT - WALL_THICK and c_int <= BOX_RIGHT + WALL_THICK) then
                red <= "1111"; green <= "1111"; blue <= "1111"; -- White
            end if;
        end if;

        -- Draw the Top Line
        if (r_int = BOX_TOP) and (c_int >= BOX_LEFT and c_int <= BOX_RIGHT) then
            if (c_int mod 16 < 8) then -- Create a dashed effect
                red <= "1111"; green <= "0000"; blue <= "0000"; -- Bright Red
            end if;
        end if;

        -- Draw a Circle (The Fruit)
        dist_sq := (c_int - CHERRY_X)**2 + (r_int - CHERRY_Y)**2;
        
        if dist_sq < (CHERRY_R**2) then
            -- Cherry Color (Bright Red)
            red   <= "1111";
            green <= "0001";
            blue  <= "0010";
        end if;

    end process;
    
    physics_driver : physics_engine
    PORT MAP(
        v_sync => v_sync,
        left => btnL,
        right => btnR,
        drop => btnDrop,
        all_fruits => all_fruits
    );
END Behavioral;
