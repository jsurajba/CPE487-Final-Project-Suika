# CPE487 Final Project - Suika
A viral, addictive "drop-and-merge" puzzle game where layers drop various fruits into a container, combining matching fruits to create larger ones, aiming to create a massive watermelon without letting the fruit overflow the top. Our poster presentation PDF can be found in our 'images' folder.

## Project Behavior
---
### Software

The current functionality of this game is limited to 32 fruits. Using the left and right buttons on the FPGA board, you can aim your fruit and then subsequently drop it using the down button (acting as our button drop). Every time a fruit drops and is not over the out of bounds line at the top, the score increases by incrementing a counter on the 16-bit FPGA display in decimal. When two fruits of the same type collide, they combine into one fruit, "upgrading" to the next level of fruit. The goal is to get watermelon. Once you either get a watermelon or reach the out of bounds line at the top, you can press the center "reset" button to start over again.

### Hardware Needed

You only need a couple pieces of hardware for this project:

1. Nexys A7-100T FPGA\
Board\
![Board](Images/board.jpg)
Board Box\
![BoardBox](Images/boardbox.jpg)
3. A device that can run Vivado
4. Micro-USB to USB-A cable
5. External Display
6. VGA, USB, and AUX to HDMI adapter\
Adapter\
![Adapter](Images/adapter.jpg)

## Steps to Run
1. Create a new project in Vivado. Add all of the supplementary .vhd files contained in 'Code' as design sources and all of the .xdc files as design constraints.
2. Connect a Nexys A7-100T FPGA to your device
3. Connect the FPGA board to an external display using the VGA to HDMI adapter
4. Click "Run Synthesis"
5. Click "Run Implementation"
6. Click "Generate Bitstream"
7. Once this is complete, click "Program Device," let the system auto-connect, and the game should appear on your display after a couple seconds.

## Inputs and Outputs
### Inputs
Our project uses the following inputs:

| Button/Switch | Action |
| ------------- | ------ |
| BTNC          | Reset/new game |
| BTNU          | Drop the current fruit |
| BTNL          | Move drop position left |
| BTNR          | Move drop position right |
| SWO           | Master enable that must be up to play |

Buttons \
![b](Images/buttons.jpg)
Switch \
![s](Images/switch.jpg)

### Outputs
The 7-segment counter that is built into the Nexys A7-100T is used to keep score. As previously stated, it increases by 1 for every fruit dropped in total. We also used the video output on the board to actually show the game on an external display.

## Summary
The initial idea came from us reminiscing our favorite simple web-based games and remembering Suika. 

Since there's not a lot of material covering a game similar to Suika in terms of physics, we had generative AI generate us skeleton code for the physics engine and created the rest of the code ourselves, modifying that skeleton code as needed.

## Project in Action
Video recording:

### Gameplay
Leveling up\
![1](Images/leveling_up.jpeg)
Game Over\
![2](Images/game_over.jpeg)

## Conclusion

### Responsibilities
Jared Surajballi
- Created the graphics code (including rectangular box and game over line)
- Transcribed the project into the README of the github repository
- Assisted in modification of physics engine

Jason Yao:
- Lead person working on modifying the physics engine
- Added project video and images to the Github repository
- Contributed updated code to Github repository

Mauricio Sanchez:
- Transcribed the project into a poster format
- Assisted in modification of physics engine

### Challenges
The most difficult challenge was by far the physics engine. We faced an issue where the fruits would bounce nonstop on other fruits, and, when it came in contact with another dropped fruit from above that didn't immediately level it up, it would sink to the bottom of the enclosed space.
