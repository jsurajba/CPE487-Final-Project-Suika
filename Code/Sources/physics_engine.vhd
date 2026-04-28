library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.fruit_pkg.all;

entity physics_engine is
    port (
        v_sync : in std_logic;
        -- Buttons for the "Aim" phase
        btnL, btnR, btnDrop : in std_logic;
        -- The output data to the renderer
        all_fruits : out fruit_array
    );
end physics_engine;

architecture Behavioral of physics_engine is
    signal fruits : fruit_array := (others => (active => '0', others => 0));
    constant GRAVITY : integer := 1;
begin
    process(v_sync)
    begin
        if rising_edge(v_sync) then
            for i in 0 to 19 loop
                if fruits(i).active = '1' then
                    -- 1. Apply Gravity
                    fruits(i).y_vel <= fruits(i).y_vel + GRAVITY;

                    -- 2. Basic Kinematics
                    fruits(i).x_pos <= fruits(i).x_pos + fruits(i).x_vel;
                    fruits(i).y_pos <= fruits(i).y_pos + fruits(i).y_vel;

                    -- 3. Simple Floor Collision (for testing)
                    if (fruits(i).y_pos + fruits(i).radius) >= 440 then
                        fruits(i).y_pos <= 440 - fruits(i).radius;
                        fruits(i).y_vel <= -(fruits(i).y_vel / 2); -- Bounce & Damping
                    end if;
                end if;
            end loop;
        end if;
    end process;
    all_fruits <= fruits;
end Behavioral;