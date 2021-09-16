#!/usr/bin/env bash
#
# NAME:
#   check_camera.sh - Check status of security cameras
#
# SYNOPSIS:
#   check_camera.sh [OPTION [ARG]]
#
# DESCRIPTION:
# Script checks if the security IP cameras have connection to the router, i.e.,
# to the wifi network and sends their status to ThingsBoard IoT platform
# for processing alarms.
# - Script has to be run under root privileges (sudo ...).
# - Script is supposed to run under cron.
# - Script sends two-value status to the IoT platform over REST API with curl.
# - All essential parameters are defined in the section of configuration parameters.
#   Their description is provided locally. Script can be configured by changing values of them.
# - Configuration parameters in the script can be overriden by the corresponding ones
#   in a configuration file or credentials file declared in the command line.
#   In the same way can be defined mandatory arguments.
# - For security reasons the credentials to IoT platform should be written
#   only in credentials file. Putting them to a command line does not prevent
#   them to be revealed by cron in email messages as a subject.
# - At camera connection outage or restoration the script sends the status just
#   once right after a change of connection status.
#
# OPTIONS:
#   -h  Help
#       Show usage description and exit.
#
#   -s  Simmulation
#       Perform dry run without sending to IoT platform.
#
#   -V  Version
#       Show version and copyright information and exit.
#
#   -c  Configs
#       Print listing of all configuration parameters.
#
#   -l  LoggingLevel
#       Logging. Level of logging intensity to syslog
#       0=none, 1=errors (default), 2=warnings, 3=info, 4=full
#
#   -o  Output
#       Level of verbose intensity.
#       0=none, 1=errors, 2=mails, 3=info (default), 4=functions, 5=full
#
#   -m  Mailing
#       Display processing messages suitable for emailing from cron.
#       It is an alias for '-o2'.
#
#   -v  Verbose
#       Display all processing messages.
#       It is an alias for '-o5'.
#
#   -f  ConfigFile
#       Configuration file for overriding default configuration parameters.
#
#   -p  CredFile
#       Credentials file with access permissions for overriding default
#       configuration parameters.
#
#   -t  StatusFile
#       Tick file for writing working status of the script.
#       Should be located in temporary file system.
#
#   -1  Force all camera connection
#       Pretend functional wifi connection to all cameras.
#
#   -2  Force no connection
#       Pretend broken wifi connection of all cameras.
#
# ARGS: None
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
CONFIG_version="0.2.0"
CONFIG_commands=('grep' 'ping') # Array of generally needed commands
CONFIG_commands_run=('curl') # List of commands for full running
CONFIG_level_logging=0  # No logging
CONFIG_flag_root=1	# Check root privileges flag
CONFIG_flag_force_active=0
CONFIG_flag_force_idle=0
CONFIG_active="ON"
CONFIG_idle="OFF"
CONFIG_status="/tmp/${CONFIG_script}.inf"  # Status file
# Cameras
CONFIG_camera_front_ip=""
CONFIG_camera_front_status=""
CONFIG_camera_back_ip=""
CONFIG_camera_back_status=""
# <- END _config


# -> BEGIN _functions

# @info: Display usage description
# @args: none
# @return: none
# @deps: none
show_help () {
	echo
	echo "${CONFIG_script} [OPTION [ARG]]"
	echo "
Check wifi connection status of all security IP cameras and send them
to ThinsBoard IoT platform.
$(process_help -o)
  -1 pretend (force) correct connection of all cameras
  -2 pretend (force) failed connection of all cameras
$(process_help -f)
"
}

# @info: Intialize log variables
# @return: LOG_* variables
# @deps: CONFIG_* variables
init_logvars () {
	LOG_camera_front=${CONFIG_active}
	LOG_camera_back=${CONFIG_active}
}

# @info: Actions at finishing script invoked by 'trap'
# @args: none
# @return: none
# @deps: Overloaded library function
stop_script () {
	show_manifest STOP
}

# @info:  Checking front camera wifi connection
# @args:  none
# @return: global config variable
# @deps:  none
check_camera_front () {
	msg="Checking front camera status"
	camera_ip=${CONFIG_camera_front_ip}
  camera_status=${CONFIG_idle}
	echo_text -hp -${CONST_level_verbose_info} "${msg}$(force_token)${sep}"
	# Dry run simulation
	if [[ ${CONFIG_flag_force_active} -eq 1 ]]
	then
		camera_status=${CONFIG_active}
	elif [[ ${CONFIG_flag_force_idle} -eq 1 ]]
	then
		camera_status=${CONFIG_idle}
	# Check connection to wifi
	else
		TestIP=${camera_ip}
		if [ -n "${TestIP}" ]
		then
			ping -c1 -w5 ${TestIP} >/dev/null
			if [ $? -eq 0 ]
			then
				camera_status=${CONFIG_active}
			else
				camera_status=${CONFIG_idle}
			fi
		fi
	fi
	echo_text -${CONST_level_verbose_info} "${camera_status}."
	log_text -IS "${msg}${sep}${camera_status}"
	if [ -n "${CONFIG_status}" ]
	then
		echo_text -ISL -${CONST_level_verbose_none} "${msg}${sep}${camera_status}." >> "${CONFIG_status}"
	fi
	CONFIG_camera_front_status=${camera_status}
}

# @info:  Checking back camera wifi connection
# @args:  none
# @return: global config variable
# @deps:  none
check_camera_back () {
	msg="Checking back camera status"
	camera_ip=${CONFIG_camera_back_ip}
  camera_status=${CONFIG_idle}
	echo_text -hp -${CONST_level_verbose_info} "${msg}$(force_token)${sep}"
	# Dry run simulation
	if [[ ${CONFIG_flag_force_active} -eq 1 ]]
	then
		camera_status=${CONFIG_active}
	elif [[ ${CONFIG_flag_force_idle} -eq 1 ]]
	then
		camera_status=${CONFIG_idle}
	# Check connection to wifi
	else
		TestIP=${camera_ip}
		if [ -n "${TestIP}" ]
		then
			ping -c1 -w5 ${TestIP} >/dev/null
			if [ $? -eq 0 ]
			then
				camera_status=${CONFIG_active}
			else
				camera_status=${CONFIG_idle}
			fi
		fi
	fi
	echo_text -${CONST_level_verbose_info} "${camera_status}."
	log_text -IS "${msg}${sep}${camera_status}"
	if [ -n "${CONFIG_status}" ]
	then
		echo_text -ISL -${CONST_level_verbose_none} "${msg}${sep}${camera_status}." >> "${CONFIG_status}"
	fi
	CONFIG_camera_back_status=${camera_status}
}

# @info:  Send data to ThingsBoard IoT platform
# @args:  none
# @return: global CONFIG_thingsboard_code variable
# @deps:  global CONFIG_camera variables
write_thingsboard () {
	local reqdata camera_front camera_back
	# Compose data item for front camera
	if [[ "${CONFIG_camera_front_status}" == "${CONFIG_active}" ]]
	then
		camera_front="true"
	elif [[ "${CONFIG_camera_front_status}" == "${CONFIG_idle}" ]]
	then
		camera_front="false"
	else
		camera_front=""
	fi
	if [ -n "${camera_front}" ]
	then
		reqdata="${reqdata}\"cameraFront\":${camera_front},"
	fi
	# Compose data item for back camera
	if [[ "${CONFIG_camera_back_status}" == "${CONFIG_active}" ]]
	then
		camera_back="true"
	elif [[ "${CONFIG_camera_back_status}" == "${CONFIG_idle}" ]]
	then
		camera_back="false"
	else
		camera_back=""
	fi
	if [ -n "${camera_back}" ]
	then
		reqdata="${reqdata}\"cameraBack\":${camera_back},"
	fi
	# Process request payload
	msg="Sending to ThingsBoard"
	if [ -n "${reqdata}" ]
	then
		reqdata=${reqdata::-1}
		reqdata="{${reqdata}}" # Create JSON object
	else
		result="no payload"
		echo_text -${CONST_level_verbose_info} "${msg}${sep}${result}. Exiting."
		log_text -FS "${msg}${sep}${result}"
		if [ -n "${CONFIG_status}" ]
		then
			echo_text -ISL -${CONST_level_verbose_none} "${msg}${sep}${result}." >> "${CONFIG_status}"
		fi
		fatal_error "${msg} failed with ${result}."
	fi
	write2thingsboard "${reqdata}"
}
# <- END _functions


# Process command line parameters
process_options $@
while getopts "${LIB_options}12" opt
do
	case "$opt" in
	1)
		CONFIG_flag_force_active=1
		CONFIG_flag_force=1
		;;
	2)
		CONFIG_flag_force_idle=1
		CONFIG_flag_force=1
		;;
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

init_script
show_configs

process_folder -t "Status" -f "${CONFIG_status}"

# -> Script execution
trap stop_script EXIT

# Initialize log variables
init_logvars

if [ -n "${CONFIG_status}" ]
then
	echo_text -h -${CONST_level_verbose_info} "Writing to status file${sep}'${CONFIG_status}'."
	echo "" > "${CONFIG_status}"
fi

check_camera_front
check_camera_back
write_thingsboard

# End of script processed by TRAP
