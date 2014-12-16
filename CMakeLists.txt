cmake_minimum_required(VERSION 2.8)

project(sunxi-bootsetup ASM C)
find_package(Threads REQUIRED)
set(CMAKE_C_FLAGS "-O2")

install_programs(/bin FILES sunxi-bootsetup-uart sunxi-bootsetup-hdmi)
install_files(/bin FILES sunxi-bootsetup-common.rb)
