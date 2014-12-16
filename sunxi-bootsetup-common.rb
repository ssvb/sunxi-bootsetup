# Copyright © 2014 Siarhei Siamashka <siarhei.siamashka@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require 'tempfile'
require 'shellwords'

##############################################################################
# Show a menu dialog and return one item name, selected by the user.
# The 'items' argument is a "item_name" => "comment_text" hash.
##############################################################################

def dialog_menu(title, text, items, default_item = nil)

    dialog_args = []
    if default_item then
        dialog_args.push("--default-item", default_item)
    end

    dialog_args.push("--clear", "--no-cancel", "--colors",
                     "--title", title.to_s,
                     "--menu", "\n" + text.to_s, "30", "110", "30")
    items.sort.each {|a| dialog_args.push(a[0], a[1]) }

    tmp = Tempfile.new('sunxi-bootsetup')
    system("dialog " + Shellwords.join(dialog_args) + " 2> #{tmp.path}")
    result = tmp.read
    tmp.close

    return if not items.has_key?(result)

    return result
end

##############################################################################
# Show a simple dialog message box
##############################################################################

def dialog_msgbox(title, text)

    dialog_args = []

    dialog_args.push("--clear", "--no-cancel",
                     "--title", title.to_s,
                     "--msgbox", "\n" + text.to_s, "30", "90")

    system("dialog " + Shellwords.join(dialog_args))
end

##############################################################################
# Lookup the list of devices and return the ones with matching parameters
# as a hash, suitable for using in the 'dialog_menu' function
##############################################################################

def find_similar_sunxi_devices(cfgfile, soc_type, dram_size, dram_bus_width)
    return if not File.exists?(cfgfile)
    fh = File.open(cfgfile)
    return if not fh
    results = {}
    fh.each_line {|l|
        # Skip comments
        next if l =~ /^\s*\#/
        # Parse the information
        if l =~ /(\S+)\s+(\S+)\s+(\d+)\s*MiB\s*\((\d+)\-bit\)/ then
            if ($2 == soc_type || soc_type == nil) &&
               ($3.to_i == dram_size || dram_size == nil) &&
               ($4.to_i == dram_bus_width || dram_bus_width == nil)
            then
                results[$1] = ""
            end
        end
    }
    fh.close
    return results
end

##############################################################################
# Check if the script is run on Allwinner (sunxi) hardware
##############################################################################

def is_sunxi_hardware()
    fh = File.open("/proc/cpuinfo")
    return nil if not fh
    fh.each_line {|l|
        if l =~ /^Hardware/ and l =~ /(Allwinner)|(sun\di)/ then
            return true
        end
    }
    return nil
end

##############################################################################
# Read and write hardware registers using devmem2
##############################################################################

VER_REG  = 0x1C00024
SID_KEY0 = (0x01c23800 + 0)
SID_KEY1 = (0x01c23800 + 4)
SID_KEY2 = (0x01c23800 + 8)
SID_KEY3 = (0x01c23800 + 12)

def mem_read_word(addr)
    result = `devmem2 #{sprintf("0x%08X", addr)} w`
    if result =~ /Value at address 0x(\h+) \(0x\h+\): 0x(\h+)/ then
        if $1.to_i(16) == addr then
            return $2.to_i(16)
        end
    end
end

def mem_write_word(addr, val)
    result = `devmem2 #{sprintf("0x%08X", addr)} w #{sprintf("0x%08X", val)}`
    if result =~ /Written 0x(\h+)/ then
        if $1.to_i(16) == val then
            return true
        end
    end
end

##############################################################################
# Get basic information about the system
##############################################################################

def get_hardware_info()
    results = { summary_string: "Unknown hardware" }
    return results if not is_sunxi_hardware()

    val = mem_read_word(VER_REG)
    return results if not val

    # Check the VER_R_EN bit and set it if necessary
    if (val & (1 << 15)) == 0 then
        mem_write_word(VER_REG, val | (1 << 15))
        val = mem_read_word(VER_REG)
    end

    # Test the SoC type
    case val >> 16
    when 0x1623
        results[:soc_type] = "sun4i"
        results[:soc_name] = "Allwinner A10"
    when 0x1625
        results[:soc_type] = "sun5i"
        case (mem_read_word(SID_KEY2) >> 12) & 0xF
        when 0
            results[:soc_name] = "Allwinner A12"
        when 3
            results[:soc_name] = "Allwinner A13"
        when 7
            results[:soc_name] = "Allwinner A10s"
        end
    when 0x1633
        results[:soc_type] = "sun6i"
        results[:soc_name] = "Allwinner A31(s)"
    when 0x1650
        results[:soc_type] = "sun8i"
        results[:soc_name] = "Allwinner A23"
    when 0x1651
        results[:soc_type] = "sun7i"
        results[:soc_name] = "Allwinner A20"
    end

    # Parse the dram info
    data = `a10-meminfo`
    dram_chip_density = 0
    dram_bus_width = 0
    dram_io_width = 0
    if data =~ /dram_clk\s*\=\s*(\d+)/ then
        results[:dram_clock] = $1.to_i
    end
    if data =~ /mbus_clk\s*\=\s*(\d+)/ then
        results[:mbus_clock] = $1.to_i
    end
    if data =~ /dram_chip_density\s*\=\s*(\d+)/ then
        dram_chip_density = $1.to_i
    end
    if data =~ /dram_bus_width\s*\=\s*(\d+)/ then
        dram_bus_width = $1.to_i
    end
    if data =~ /dram_io_width\s*\=\s*(\d+)/ then
        dram_io_width = $1.to_i
    end
    results[:dram_size] = dram_bus_width * dram_chip_density /
                          (dram_io_width * 8)
    results[:dram_bus_width] = dram_bus_width

    results[:summary_string] = sprintf("SoC: %s",
        (results[:soc_name] or "unknown"))

    if results[:dram_clock] then
        results[:summary_string] += sprintf(", DRAM: %d MiB, %d-bit, %d MHz",
                                            results[:dram_size],
                                            results[:dram_bus_width],
                                            results[:dram_clock])
    end

    if results[:mbus_clock] && results[:mbus_clock] != 0 then
        results[:summary_string] += sprintf(", MBUS: %d MHz",
                                            results[:mbus_clock])
    end

    return results
end

##############################################################################

def read_file(dir = nil, name)
    fullname = dir ? File.join(dir, name) : name
    return if not File.exists?(fullname)
    fh = File.open(fullname, "rb")
    data = fh.read
    fh.close
    return data
end

##############################################################################

def do_install_uboot(uboot_directory, hardware_info)
    cfgfile = File.join(uboot_directory, "sunxi-boards.cfg")

    similar_devices = find_similar_sunxi_devices(
        cfgfile,
        hardware_info[:soc_type],
        hardware_info[:dram_size],
        hardware_info[:dram_bus_width])

    if not similar_devices then
        dialog_msgbox(hardware_info[:summary_string],
                  sprintf("Error: can't load '%s'", cfgfile))
        return
    end

    if similar_devices.size == 0 then
        dialog_msgbox(hardware_info[:summary_string],
                      "Looks like your hardware can't possibly " +
                      "match any of the supported devices.")
        return
    end

    text = "Please select your device from the list below. " +
           "This list has been already partially reduced by " +
           "weeding out some of the incompatible devices (based " +
           "on the automatically detected Allwinner SoC variant, " +
           "DRAM size and bus width).\n" +
           "\n" +
           "\\Zb\\Z1Warning: if you don't see the exact name of your " +
           "device in the list, at least please don't try to " +
           "make some random choice. Using incorrect settings is " +
           "a bad idea, in the worst case this may even damage the " +
           "hardware."

    board_name = dialog_menu(hardware_info[:summary_string],
                             text,
                             similar_devices)

    return if not board_name

    uboot_binary_name = "u-boot-sunxi-with-spl-#{board_name}.bin"
    uboot_binary_path = File.join(uboot_directory, uboot_binary_name)

    return if not File.exists?(uboot_binary_path)

    text  = "We are about to install the u-boot bootloader, compiled " +
            "for the '#{board_name}' board. The installation is done " +
            "to the SD card by executing the following commands:\n" +
            "\n" +
            "\\Zb\\Z6# dd if=#{uboot_binary_path} \\\n" +
            "     of=/dev/mmcblk0 bs=1024 seek=8\n" +
            "# sync && reboot\n" +
            "\n\\Zn"

    if not File.exists?("/mnt/mmcblk0p1/boot/boot.scr") then
        text += "After reboot, the installed u-boot is expected to search " +
                "for the '/boot/boot.scr' file in the first ext4 " +
                "formatted partitition of the SD card to find the " +
                "information about the linux kernel to load. " +
                "It appears that this particular SD card still does not " +
                "have a complete linux system installed.\n\n"
    end

    text += "\\Zb\\Z1Warning: there is no way back and this " +
            "installation wizard will be replaced by the newly " +
            "installed u-boot. Be sure to make the right choice here:\n"

    confirmation_menu = {}
    confirmation_menu["1"] = "Cancel and return to the main menu"
    confirmation_menu["2"] = "Yes, please do it. I'm sure that my hardware is '#{board_name}'"

    case dialog_menu(hardware_info[:summary_string], text, confirmation_menu)
    when "1"
        return
    when "2"
        system("dd if=#{uboot_binary_path} of=/dev/mmcblk0 bs=1024 seek=8")
        system("sync && reboot")
        while true do
            sleep(1)
        end
    end
end

##############################################################################

def do_main_menu(uart_console)

    hardware_info = get_hardware_info()

    intro_text = "Right now your device is running in a 'lowest common " +
                 "denominator' hardware configuration with just a minimal set " +
                 "of peripherals enabled: SD card, UART serial console, HDMI " +
                 "video output and partial USB host support. The CPU and DRAM " +
                 "clock speeds are also much lower than normal."
    intro_text += "\n\n"

    if !uart_console && (hardware_info[:soc_type] == "sun4i" ||
                         hardware_info[:soc_type] == "sun7i")
    then
        intro_text += "If there are \\Zb\\Z6USB host ports\\Zn in your device, then some of them " +
                      "might be already functional. You can try to plug a USB keyboard " +
                      "and use it for navigating in this menu. Allwinner A10/A20 devices " +
                      "typically use PH03/PH06 GPIO pins to control the switches, which " +
                      "enable/disable the USB power. But some of the A10/A20 devices may " +
                      "be still using different GPIO pins. If none of the USB host ports " +
                      "works, please also consider trying a powered USB hub before giving up."
        intro_text += "\n\n"
    end

    if !uart_console && hardware_info[:soc_type] == "sun5i"
    then
        intro_text += "If you have \\Zb\\Z6USB host ports\\Zn in your device, then some of them " +
                      "might work, albeit with a little bit of hassle. You can try to plug a " +
                      "powered USB hub to the USB host port in your device. And also " +
                      "plug a USB keyboard to this powered USB hub. Then use the " +
                      "keyboard for navigating in this menu. Note: the powered USB hub " +
                      "may be only needed at this point because we don't know which GPIO " +
                      "pins to use for enabling the USB power (and these pins are very " +
                      "board-specific on A13/A10s hardware)."
        intro_text += "\n\n"
    end

    if not uart_console
    then
        intro_text += "Even if there are no USB host ports or they don't work properly " +
                      "in this configuration, please don't give up yet. It is alternatively " +
                      "possible to use \\Zb\\Z6the FEL button\\Zn (if your device has one). " +
                      "Short button press means ARROW DOWN. Long button press means ENTER."
        intro_text += "\n\n"
        intro_text += "And even if none of the USB/FEL input methods work, the same menu " +
                      "should be also accessible on the UART serial console."
        intro_text += "\n\n"
    end


    uboot_directory = "/mnt/mmcblk0p1/boot/setup/u-boot-binaries"

    config_file  = "sunxi-boards.cfg"

    main_menu = {}

    description = read_file(uboot_directory, "description.txt")
    if description then
        main_menu["1"] = "Install " + description
    else
        intro_text += "Warning: missing proper directory with u-boot binaries at " +
                      uboot_directory
        intro_text += "\n\n"
    end

    main_menu["2"]  = "Login as 'root' to the initramfs busybox shell"

    intro_text += "Select your action:\n"

    while true do
        case dialog_menu(hardware_info[:summary_string], intro_text, main_menu)
        when "1"
            do_install_uboot(uboot_directory, hardware_info)
        when "2"
            exec("login -f root")
        end
    end
end
