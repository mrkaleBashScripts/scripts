#!/usr/bin/env bash
#
# NAME:
#   check_infra.sh - Check status of infrastructure
#
# SYNOPSIS:
#   check_infra.sh [OPTION [ARG]] ICSE_devfile [log_file]
#
# DESCRIPTION:
# Script checks if the infrastructure on the weekend house is functional. If it
# detects some failure, it sends signal to ThingsBoard IoT platform running
# on local server to create alarm(s) about it.
#
# - The script checks if supplying of the local server is from electrical mains
#   or battery.
# - The scripts checks if local server has connection to the internet, i.e.,
#   the router is functional and can pings to selected external IP addresss.
# - The script controls the USB relay board ICSE013A with 2 relays both at once.
# - One of relays supplies the internet router and works in opposite order, i.e.,
#   Normally Closed ports are utilized and relay supplies in OFF state.
# - At detection internet outage, the script starts countdown and executes itself
#   3 times. If there is still outage, the script turns the relay ON, which means
#   switching OFF the router. Right before it the script initializes the relay
#   board for sure, even if it is initialized at system boot or USB cable plug-in.
#   In this state the script starts new countdown and executes itself 3 times
#   as a waiting period for discharching the router.
# - Then the script turns the relay OFF again, which connects mains to the router
#   and starts the entire process again. If the internet connection is restored
#   during that process, the script waits to another internet outage for rebooting
#   router again.
# - Entire process with turning ON and OFF the relays is repeated until the
#   internet connection is restored even if it might be useless.
#
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
#   -0  Force ignoring the relay control
#       Do not turn off router in either case.
#
#   -1  Force internet connection
#       Pretend functional internet.
#
#   -2  Force no connection
#       Pretend broken internet connection.
#
#   -3  Force mains supply
#       Pretend powering from electrical mains.
#
#   -4  Force battery supply
#       Pretend failed electrical mains.
#
#   -5  Force all camera connection
#       Pretend functional wifi connection to all cameras.
#
#   -6  Force no camera connection
#       Pretend broken wifi connection of all cameras.
#
# ARGS:
#   ICSE_devfile  Device file of a relay board in '/dev' folder
#   log_file      Alternative log file to default one for persisting working
#                 variables
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
CONFIG_version="0.6.0"
CONFIG_commands=('grep' 'ping') # Array of generally needed commands
CONFIG_commands_run=('curl' 'xxd') # List of commands for full running
CONFIG_flag_root=1	# Check root privileges flag
CONFIG_flag_force_norelay=0
CONFIG_flag_force_mains=0
CONFIG_flag_force_batt=0
CONFIG_flag_force_inet=0
CONFIG_flag_force_noinet=0
CONFIG_flag_force_cam=0
CONFIG_flag_force_nocam=0
CONFIG_active="ON"
CONFIG_idle="OFF"
CONFIG_mains_status=""
CONFIG_inet_status=""
CONFIG_camera_front_status=""
CONFIG_camera_back_status=""
CONFIG_inet_ips=('8.8.4.4' '1.0.0.1' '208.67.220.220')	# External test IPs: Google, Cloudflare, OpenDNS.
CONFIG_icse_file="/dev/null"	# Device file of the relay board
CONFIG_icse_delay=1	# Delay in seconds between control bytes sending
CONFIG_camera_front_ip=""
CONFIG_camera_back_ip=""
CONFIG_log_file="/tmp/${CONFIG_script}.dat"	# Persistent log file
CONFIG_log_count=3	# Count-down periods
CONFIG_status="/tmp/${CONFIG_script}.inf"  # Status file
# <- END _config


# -> BEGIN _functions

# @info: Display usage description
# @args: none
# @return: none
# @deps: none
show_help () {
	echo
	echo "${CONFIG_script} [OPTION [ARG]] ICSE_devfile [log_file]"
	echo "
Check internet connection status and send it to ThinsBoard IoT platform.
Temporarily turn off the ICSE relay for rebooting a router after a couple of
running periods.
$(process_help -o)
  -0 force USB relay ignoring (never turn it off)
  -1 pretend (force) mains power supply
  -2 pretend (force) battery power supply
  -3 pretend (force) correct internet connection
  -4 pretend (force) failed internet connection
  -5 pretend (force) correct connection of all cameras
  -6 pretend (force) failed connection of all cameras

  ICSE_devfile: device file of a relay board in '/dev' folder
  log_file: alternative log file to default one for persisting working variables
$(process_help -f)
"
}

# @info: Intialize log variables
# @return: LOG_* variables
# @deps: CONFIG_* variables
init_logvars () {
	LOG_relay=${CONFIG_active}
	LOG_period=${CONFIG_log_count}
	LOG_toggle=0
}

# @info: Save log variables to log file
# @args: none
# @return: none
# @deps: LOG_* variables
save_logvars () {
	if [[ -n "${CONFIG_inet_status}" ]]
	then
		if [[ "${CONFIG_inet_status}" == "${CONFIG_idle}" ]]
		then
			set | grep "^LOG_" > "${CONFIG_log_file}"
		elif [[ -f "${CONFIG_log_file}" ]]
		then
			rm "${CONFIG_log_file}"
		fi
	fi
}

# @info: Actions at finishing script invoked by 'trap'
# @args: none
# @return: none
# @deps: Overloaded library function
stop_script () {
	save_logvars
	show_manifest STOP
}

# @info:  Checking mains status
# @args:  none
# @return: global config variable
# @deps:  Overloaded library function
check_mains () {
	local file result logpfx
	msg="Checking mains power supply status"
	logpfx="I"
	CONFIG_mains_status=${CONFIG_idle}
	echo_text -hp -${CONST_level_verbose_info} "${msg}$(force_token)${sep}"
	# Dry run simulation
	if [[ ${CONFIG_flag_force_mains} -eq 1 ]]
	then
		CONFIG_mains_status=${CONFIG_active}
	elif [[ ${CONFIG_flag_force_batt} -eq 1 ]]
	then
		CONFIG_mains_status=${CONFIG_idle}
		logpfx="E"
	else
		CONFIG_mains_status=""
		# WSL2
		if [ -z "${CONFIG_mains_status}" ]
		then
			grep "WSL" /proc/version >/dev/null
			result=$?
			if [[ ${result} -eq 0 ]]
			then
				file="/sys/class/power_supply/AC1/online"
				result=$(cat ${file})
				if [[ ${result} -eq 1 ]]
				then
					CONFIG_mains_status=${CONFIG_active}
				elif [[ ${result} -eq 0 ]]
				then
					CONFIG_mains_status=${CONFIG_idle}
					logpfx="E"
				fi
			fi
		fi
		# WS1
		if [ -z "${CONFIG_mains_status}" ]
		then
			grep "Microsoft" /proc/version >/dev/null
			result=$?
			if [[ ${result} -eq 0 ]]
			then
				file="/sys/class/power_supply/battery/status"
				result=$(cat ${file})
				if [[ ${result} == "Discharging" ]]
				then
					CONFIG_mains_status=${CONFIG_idle}
					logpfx="E"
				else
					CONFIG_mains_status=${CONFIG_active}
				fi
			fi
		fi
		# Linux
		if [ -z "${CONFIG_mains_status}" ]
		then
			grep "Linux" /proc/version >/dev/null
			result=$?
			if [[ ${result} -eq 0 ]]
			then
				file="/sys/class/power_supply/ADP1/online"
				result=$(cat ${file})
				if [[ ${result} -eq 1 ]]
				then
					CONFIG_mains_status=${CONFIG_active}
				elif [[ ${result} -eq 0 ]]
				then
					CONFIG_mains_status=${CONFIG_idle}
					logpfx="E"
				fi
			fi
		fi
	fi
	echo_text -${CONST_level_verbose_info} "${CONFIG_mains_status}."
	log_text -${logpfx}S "${msg}${sep}${CONFIG_mains_status}"
	status_text -a${logpfx} "${msg}${sep}${CONFIG_mains_status}"
}

# @info:  Checking internet connection
# @args:  none
# @return: global config variable
# @deps:  none
check_inet () {
	local msg period
	msg="Checking internet connection status"
	logpfx="E"
	CONFIG_inet_status=${CONFIG_idle}
	echo_text -hp -${CONST_level_verbose_info} "${msg}$(force_token)${sep}"
	# Dry run simulation
	if [[ ${CONFIG_flag_force_inet} -eq 1 ]]
	then
		CONFIG_inet_status=${CONFIG_active}
		logpfx="I"
	elif [[ ${CONFIG_flag_force_noinet} -eq 1 ]]
	then
		:
	# Check connection to internet
	else
		for ip in ${CONFIG_inet_ips[@]}
		do
			ping -c1 -w5 ${ip} >/dev/null
			if [ $? -eq 0 ]
			then
				CONFIG_inet_status=${CONFIG_active}
				logpfx="I"
				break
			fi
		done
	fi
	echo_text -${CONST_level_verbose_info} "${CONFIG_inet_status}."
	period=""
	if [[ "${CONFIG_inet_status}" == "${CONFIG_idle}" ]]
	then
		period=" ($((${CONFIG_log_count}-${LOG_period}+1)))"
	fi
	log_text -${logpfx}S "${msg}${period}${sep}${CONFIG_inet_status}"
	status_text -a${logpfx} "${msg}${period}${sep}${CONFIG_inet_status}"
}

# @info: Toggle relay
# @return: LOG_* variables
# @deps: CONFIG_* variables
relay_toggle () {
	local msg result init control_byte msgrel msgini
	msgrel="relay '${CONFIG_icse_file}'"
	msg="Toggling ${msgrel}"
	msgini="Initializing ${msgrel}"
	echo_text -hp -${CONST_level_verbose_info} "${msg}$(dryrun_token)"
	if [[ "${LOG_relay}" == "${CONFIG_active}" ]]
	then
		# Initialize relay for sure (even if done at boot or USB plug-in)
		init="50 50 50 50 51 52 00 00"
		# Control both relays on the board at once
		control_byte="03"
		LOG_relay=${CONFIG_idle}
	else
		init=""
		control_byte="00"
		LOG_relay=${CONFIG_active}
	fi
	if [[ $CONFIG_flag_dryrun -ne 0 ]]
	then
		:
	# Do not control relay in either case
	elif [[ ${CONFIG_flag_force_norelay} -ne 0 ]]
	then
		msg="${msg}$(force_token) intact"
	else
		# Initialize
		if [ -n "${init}" ]
		then
			echo "${init}" | xxd -r -p > "${CONFIG_icse_file}"
			sleep ${CONFIG_icse_delay}
			log_text -WS "${msgini}"
			status_text -aW "${msgini}"
		fi
		# Control
		echo "${control_byte}" | xxd -r -p > "${CONFIG_icse_file}"
	fi
	LOG_period=${CONFIG_log_count}
	LOG_toggle=1
	result="${sep}to ${LOG_relay} by ${control_byte}."
	echo_text -${CONST_level_verbose_info} "${result}"
	log_text -WS "${msg}${result}"
	status_text -aW "${msg}${result}"
}

# @info: Toggle relay
# @return: LOG_* variables
# @deps: CONFIG_* variables
relay_control () {
	local msg
	msg="Control relay '${CONFIG_icse_file}'${sep}"
	if [[ "${CONFIG_inet_status}" == "${CONFIG_idle}" ]]
	then
		((LOG_period--))
		msg="${msg}countdown${sep}Inet ${CONFIG_inet_status}"
		msg="${msg}, Relay ${LOG_relay}, Period ${LOG_period}."
		echo_text -h -${CONST_level_verbose_info} "${msg}"
		if [[ ${LOG_period} -le 0 ]]
		then
			relay_toggle
		fi
	elif [[ "${CONFIG_inet_status}" == "${CONFIG_active}"
			&& "${LOG_relay}" == "${CONFIG_idle}" ]]
	then
		relay_toggle
	fi
}

# @info:  Checking front camera wifi connection
# @args:  none
# @return: global config variable
# @deps:  none
check_camera_front () {
	local msg logpfx
	msg="Checking camera status${sep}front"
	logpfx="I"
  CONFIG_camera_front_status=${CONFIG_idle}
	echo_text -hp -${CONST_level_verbose_info} "${msg}$(force_token)${sep}"
	# Dry run simulation
	if [[ ${CONFIG_flag_force_cam} -eq 1 ]]
	then
		CONFIG_camera_front_status=${CONFIG_active}
	elif [[ ${CONFIG_flag_force_nocam} -eq 1 ]]
	then
		CONFIG_camera_front_status=${CONFIG_idle}
		logpfx="E"
	# Check connection to wifi
	else
		if [ -n "${CONFIG_camera_front_ip}" ]
		then
			ping -c1 -w5 ${CONFIG_camera_front_ip} >/dev/null
			if [ $? -eq 0 ]
			then
				CONFIG_camera_front_status=${CONFIG_active}
			else
				CONFIG_camera_front_status=${CONFIG_idle}
				logpfx="E"
			fi
		fi
	fi
	echo_text -${CONST_level_verbose_info} "${CONFIG_camera_front_status}."
	log_text -${logpfx}S "${msg}${sep}${CONFIG_camera_front_status}"
	status_text -a${logpfx} "${msg}${sep}${CONFIG_camera_front_status}"
}

# @info:  Checking back camera wifi connection
# @args:  none
# @return: global config variable
# @deps:  none
check_camera_back () {
	local msg logpfx
	msg="Checking camera status${sep}back"
	logpfx="I"
  CONFIG_camera_back_status=${CONFIG_idle}
	echo_text -hp -${CONST_level_verbose_info} "${msg}$(force_token)${sep}"
	# Dry run simulation
	if [[ ${CONFIG_flag_force_cam} -eq 1 ]]
	then
		CONFIG_camera_back_status=${CONFIG_active}
	elif [[ ${CONFIG_flag_force_nocam} -eq 1 ]]
	then
		CONFIG_camera_back_status=${CONFIG_idle}
		logpfx="E"
	# Check connection to wifi
	else
		if [ -n "${CONFIG_camera_back_ip}" ]
		then
			ping -c1 -w5 ${CONFIG_camera_back_ip} >/dev/null
			if [ $? -eq 0 ]
			then
				CONFIG_camera_back_status=${CONFIG_active}
			else
				CONFIG_camera_back_status=${CONFIG_idle}
				logpfx="E"
			fi
		fi
	fi
	echo_text -${CONST_level_verbose_info} "${CONFIG_camera_back_status}."
	log_text -${logpfx}S "${msg}${sep}${CONFIG_camera_back_status}"
	status_text -a${logpfx} "${msg}${sep}${CONFIG_camera_back_status}"
}

# @info:  Send data to ThingsBoard IoT platform
# @args:  none
# @return: global CONFIG_thingsboard_code variable
# @deps:  global CONFIG_inet variables
write_thingsboard () {
	local reqdata item logpfx
	logpfx="I"
	# Compose data items for power supply status
	item=""
	if [[ "${CONFIG_mains_status}" == "${CONFIG_active}" ]]
	then
		item="true"
	elif [[ "${CONFIG_mains_status}" == "${CONFIG_idle}" ]]
	then
		item="false"
	fi
	if [ -n "${item}" ]
	then
		reqdata="${reqdata}\"powerSupply\":${item},"
	fi
	# Compose data item for internet connection status only at mains
	if [[ "${CONFIG_mains_status}" == "${CONFIG_active}" ]]
	then
		item=""
		if [[ "${CONFIG_inet_status}" == "${CONFIG_active}" ]]
		then
			item="true"
		elif [[ "${CONFIG_inet_status}" == "${CONFIG_idle}" ]]
		then
			item="false"
		fi
		if [ -n "${item}" ]
		then
			reqdata="${reqdata}\"inetConnect\":${item},"
		fi
		# Compose data item for relay toggling
		item=""
		if [[ ${LOG_toggle} -eq 1 ]]
		then
			if [[ "${LOG_relay}" == "${CONFIG_active}" ]]
			then
				item="true"
			elif [[ "${LOG_relay}" == "${CONFIG_idle}" ]]
			then
				item="false"
			fi
			LOG_toggle=0
		# Relay turned on outside the script
		elif [[ "${CONFIG_inet_status}" == "${CONFIG_active}" && "${LOG_relay}" == "${CONFIG_idle}" ]]
		then
				item="true"
		fi
		if [ -n "${item}" ]
		then
			reqdata="${reqdata}\"inetRelay\":${item},"
		fi
		# Compose data item for camera connection status only at internet available
		if [[ "${CONFIG_inet_status}" == "${CONFIG_active}" ]]
		then
			# Compose data item for front camera
			item=""
			if [[ "${CONFIG_camera_front_status}" == "${CONFIG_active}" ]]
			then
				item="true"
			elif [[ "${CONFIG_camera_front_status}" == "${CONFIG_idle}" ]]
			then
				item="false"
			fi
			if [ -n "${item}" ]
			then
				reqdata="${reqdata}\"cameraFront\":${item},"
			fi
			# Compose data item for back camera
			item=""
			if [[ "${CONFIG_camera_back_status}" == "${CONFIG_active}" ]]
			then
				item="true"
			elif [[ "${CONFIG_camera_back_status}" == "${CONFIG_idle}" ]]
			then
				item="false"
			fi
			if [ -n "${item}" ]
			then
				reqdata="${reqdata}\"cameraBack\":${item},"
			fi
		fi
	fi
	# Process request payload
	msg="Sending to ThingsBoard"
	if [ -n "${reqdata}" ]
	then
		reqdata=${reqdata::-1}
		reqdata="{${reqdata}}" # Create JSON object
		echo_text -h -${CONST_level_verbose_info} "${msg}${sep}${reqdata}."
	else
		result="no payload"
		logpfx="E"
		echo_text -${CONST_level_verbose_info} "${msg}${sep}${result}. Exiting."
		status_text -a${logpfx} "${msg}${sep}${result}"
		fatal_error "${msg} failed with ${result}."
	fi
	write2thingsboard "${reqdata}"
}
# <- END _functions


# Process command line parameters
process_options $@
while getopts "${LIB_options}0123456" opt
do
	case "$opt" in
	0)
		CONFIG_flag_force_norelay=1
		CONFIG_flag_force=1
		;;
	1)
		CONFIG_flag_force_mains=1
		CONFIG_flag_force=1
		;;
	2)
		CONFIG_flag_force_batt=1
		CONFIG_flag_force=1
		;;
	3)
		CONFIG_flag_force_inet=1
		CONFIG_flag_force=1
		;;
	4)
		CONFIG_flag_force_noinet=1
		CONFIG_flag_force=1
		;;
	5)
		CONFIG_flag_force_cam=1
		CONFIG_flag_force=1
		;;
	6)
		CONFIG_flag_force_nocam=1
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

# Process non-option arguments
shift $(($OPTIND-1))
# Relay device file
if [ -n "$1" ]
then
	CONFIG_icse_file="$1"
fi
# Log file
if [ -n "$2" ]
then
	CONFIG_log_file="$2"
fi

init_script
show_configs

process_folder -t "ICSE '/dev'" -fe "${CONFIG_icse_file}"
process_folder -t "Log" -cfe "${CONFIG_log_file}"
process_folder -t "Status" -f "${CONFIG_status}"

# -> Script execution
trap stop_script EXIT

# Initialize log variables
init_logvars

# Update log variables from log file
if [ -s "${CONFIG_log_file}" ]
then
	source "${CONFIG_log_file}"
fi

# Initialize status file
status_text

check_mains
# Do not check internet and control relay when there is no power supply
if [[ "${CONFIG_mains_status}" == "${CONFIG_active}" ]]
then
	check_inet
	relay_control
	if [[ "${CONFIG_inet_status}" == "${CONFIG_active}" ]]
	then
		check_camera_front
		check_camera_back
	fi
fi
write_thingsboard

# End of script processed by TRAP
