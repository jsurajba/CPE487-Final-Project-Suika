library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package fruit_pkg is
    -- Define what data every single fruit needs
    type fruit_state is record
        active : std_logic;
        x_pos  : integer range 0 to 639;
        y_pos  : integer range 0 to 479;
        x_vel  : integer range -15 to 15;
        y_vel  : integer range -15 to 15;
        radius : integer range 0 to 100;
        tier   : integer range 0 to 10; -- 0 = Cherry, 10 = Watermelon
    end record;

    -- Create a "Bank" of 20 fruits
    type fruit_array is array (0 to 19) of fruit_state;
end package;