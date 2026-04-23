LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

ENTITY vga_sync IS
    PORT (
        pixel_clk : IN STD_LOGIC;
        red_in    : IN STD_LOGIC_VECTOR (3 DOWNTO 0); -- Full 4-bit color
        green_in  : IN STD_LOGIC_VECTOR (3 DOWNTO 0);
        blue_in   : IN STD_LOGIC_VECTOR (3 DOWNTO 0);
        red_out   : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
        green_out : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
        blue_out  : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
        hsync     : OUT STD_LOGIC;
        vsync     : OUT STD_LOGIC;
        pixel_row : OUT STD_LOGIC_VECTOR (10 DOWNTO 0);
        pixel_col : OUT STD_LOGIC_VECTOR (10 DOWNTO 0)
    );
END vga_sync;

ARCHITECTURE Behavioral OF vga_sync IS
    SIGNAL h_cnt, v_cnt : STD_LOGIC_VECTOR (10 DOWNTO 0) := (others => '0');

    -- Constants for 640x480 @ 60Hz (Pixel Clock: 25.175 MHz)
    CONSTANT H      : INTEGER := 640;
    CONSTANT V      : INTEGER := 480;
    CONSTANT H_FP   : INTEGER := 16;
    CONSTANT H_BP   : INTEGER := 48;
    CONSTANT H_SYNC : INTEGER := 96;
    CONSTANT V_FP   : INTEGER := 10;
    CONSTANT V_BP   : INTEGER := 33;
    CONSTANT V_SYNC : INTEGER := 2;

    -- Total line/frame limits
    CONSTANT H_MAX  : INTEGER := H + H_FP + H_SYNC + H_BP; -- 800
    CONSTANT V_MAX  : INTEGER := V + V_FP + V_SYNC + V_BP; -- 525

BEGIN
    sync_pr : PROCESS(pixel_clk)
        VARIABLE video_on : STD_LOGIC;
    BEGIN
        IF rising_edge(pixel_clk) THEN
            -- Horizontal Counter
            IF (h_cnt >= H_MAX - 1) THEN
                h_cnt <= (others => '0');
            ELSE
                h_cnt <= h_cnt + 1;
            END IF;

            -- Vertical Counter (increments when h_cnt finishes a line)
            IF (h_cnt = H_MAX - 1) THEN
                IF (v_cnt >= V_MAX - 1) THEN
                    v_cnt <= (others => '0');
                ELSE
                    v_cnt <= v_cnt + 1;
                END IF;
            END IF;

            IF (h_cnt >= H + H_FP) AND (h_cnt < H + H_FP + H_SYNC) THEN
                hsync <= '0';
            ELSE
                hsync <= '1';
            END IF;

            IF (v_cnt >= V + V_FP) AND (v_cnt < V + V_FP + V_SYNC) THEN
                vsync <= '0';
            ELSE
                vsync <= '1';
            END IF;

            -- Generate Video Signals and Pixel Address
            IF (h_cnt < H) AND (v_cnt < V) THEN  
                video_on := '1';
                pixel_col <= h_cnt;
                pixel_row <= v_cnt;
            ELSE
                video_on := '0';
                pixel_col <= (others => '0');
                pixel_row <= (others => '0');
            END IF;

            -- Color blanking logic
            IF video_on = '1' THEN
                red_out   <= red_in;
                green_out <= green_in;
                blue_out  <= blue_in;
            ELSE
                red_out   <= "0000";
                green_out <= "0000";
                blue_out  <= "0000";
            END IF;
        END IF;
    END PROCESS;
END Behavioral;