#!/usr/bin/env bash
#
# NAME:
#   icse_init.sh - Initialize ICSE relays with USB port
#
# SYNOPSIS:
#   icse_init.sh [OPTION [ARG]] ICSE_devfile
#
# DESCRIPTION:
# Script initialize USB relay ICSE012A	ICSE013A	ICSE014A for receiving control
# bytes.
# - Script should be triggered by an udev rule at boot time. Then a relay can
#   be controlled just by data bytes.
# - Script has to be run under root privileges (sudo ...).
# - Script is supposed to run under cron.
# - Script sends intialization byte (0x50) and control byte (0x51) to a relay
#   board and turns off all relays on a board.
# - All essential parameters are defined in the section of configuration parameters.
#   Their description is provided locally. Script can be configured by changing values of them.
# - Configuration parameters in the script can be overriden by the corresponding ones
#   in a configuration file or credentials file declared in the command line.
#   In the same way can be defined mandatory arguments.
# - For security reasons the credentials to IoT platform should be written
#   only in credentials file. Putting them to a command line does not prevent
#   them to be revealed by cron in email messages as a subject.
#
# OPTIONS:
#   -h
#       Help. Show usage description and exit.
#   -s
#       Simmulation. Perform dry run without sending to IoT platform.
#   -V
#       Version. Show version and copyright information and exit.
#   -c
#       Configs. Print listing of all configuration parameters.
#   -o
#       Output. Level of verbose intensity.
#       0=none, 1=errors, 2=mails, 3=info (default), 4=functions, 5=full
#   -m
#       Mailing. Display processing messages suitable for emailing from cron.
#       It is an alias for '-o2'.
#   -v
#       Verbose. Display all processing messages.
#       It is an alias for '-o5'.
#
#   -f  ConfigFile
#       Configuration file for overriding default configuration parameters.
#
#   -p  CredFile
#       Credentials file with access permissions for overriding default
#       configuration parameters.
#
# ARGS:
#   ICSE_devfile  Device file of a relay board in '/dev' folder
#
# LICENSE:
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#

# Load library file
LIB_name="scripts_lib"
for lib in "$LIB_name"{.sh,}
do
	LIB_file="$(command -v "$lib")"
	if [ -z "$LIB_file" ]
	then
		LIB_file="$(dirname $0)/$lib"
	fi
	if [ -f "$LIB_file" ]
	then
		source "$LIB_file"
		unset -v LIB_name LIB_file
		break
	fi
done
if [ "$LIB_name" ]
then
	echo "!!! ERROR -- No file found for library name '$LIB_name'."  1>&2
	exit 1
fi

# -> BEGIN _config
CONFIG_copyright="(c) 2021 Libor Gabaj <libor.gabaj@gmail.com>"
CONFIG_version="0.1.0"
CONFIG_commands=('xxd') # Array of generally needed commands
CONFIG_commands_run=('') # List of commands for full running
CONFIG_level_logging=0  # No logging
CONFIG_flag_root=0	# Check root privileges flag
CONFIG_icse_file=""	# Device file of the relay board
CONFIG_icse_delay=1	# Delay in seconds between control bytes sending
# <- END _config


# -> BEGIN _functions

# @info:	Display usage description
# @args:	none
# @return:	none
# @deps:	none
show_help () {
	echo
	echo "${CONFIG_script} [OPTION [ARG]] ICSE_devfile"
	echo "
Initialize particular ICSE relay board.
$(process_help -b)

  ICSE_devfile: device file of a relay board in '/dev' folder
$(process_help -f)
"
}

# @info:	Actions at finishing script invoked by 'trap'
# @args:	none
# @return:	none
# @deps:	Overloaded library function
stop_script () {
	show_manifest STOP
}

# Process command line parameters
process_options $@
while getopts "${LIB_options}12" opt
do
	case "$opt" in
	\?)
		msg="Unknown option '-$OPTARG'."
		fatal_error "$msg $help"
		;;
	:)
		case "$OPTARG" in
		*)
			msg="Missing argument for option '-$OPTARG'."
			;;
		esac
		fatal_error "$msg $help"
	esac
done

# Process non-option arguments
shift $(($OPTIND-1))
# ICSE file
if [ -n "$1" ]
then
	CONFIG_icse_file="$1"
fi

init_script

process_folder -t "ICSE /dev" -fe "${CONFIG_icse_file}"

show_configs

# -> Script execution
trap stop_script EXIT

# Processing
msg="Initializing ICSE device ${CONFIG_icse_file}"
echo_text -hp -${CONST_level_verbose_info} "${msg} ... "
init="50 50 50 50 51 52 00 00"
echo "${init}" | xxd -r -p > "${CONFIG_icse_file}" ; sleep ${CONFIG_icse_delay}
echo_text -${CONST_level_verbose_info} "OK"

# End of script processed by TRAP
