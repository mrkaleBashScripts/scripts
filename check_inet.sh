#!/usr/bin/env bash
#
# NAME:
#   check_inet.sh - Check status of internet connection
#
# SYNOPSIS:
#   check_inet.sh [OPTION [ARG]] ICSE_devfile [log_file]
#
# DESCRIPTION:
# Script checks if the local server has connection to the internet, i.e.,
# the router is functional and sends its status to ThingsBoard IoT platform
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
# - The script controls the USB relay board ICSE013A with 2 relays both at once.
# - One of relay supplies the internet router and work in oposite order, i.e.,
#   Normally Closed ports are utilized and relay supplies in OFF state.
# - At detection internet outage, the script starts countdown and executes itself
#   3 times. If there is still outage, the script turns the relay ON, which means
#   switching OFF the router. In this state the script starts new countdown
#   and executes itself 3 times as a waiting period for discharching the router.
#   Then the script turns the relay OFF again, which connects mains to the router
#   and starts the entire process again. If the internet connection is restored
#   during that process, the script waits to another internet outage for rebooting
#   router again.
# - Entire process with turning ON and OFF the relays is repeated until the
#   internet connection is restored even if it might be useless.
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
#   -t StatusFile
#       Tick file for writing working status of the script.
#       Should be located in temporary file system.
#
#   -1  Force internet connection
#       Pretend function internet.
#
#   -2  Force no connection
#       Pretend broken internet connection.
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
CONFIG_version="0.3.0"
CONFIG_commands=('grep' 'ping' 'xxd') # Array of generally needed commands
CONFIG_commands_run=('curl') # List of commands for full running
CONFIG_level_logging=0  # No logging
CONFIG_flag_root=1	# Check root privileges flag
CONFIG_flag_force_inet=0
CONFIG_flag_force_idle=0
CONFIG_inet_ip="8.8.4.4"	# External test IP address of Google, inc.
CONFIG_active="ON"
CONFIG_idle="OFF"
CONFIG_inet_status=""
CONFIG_thingsboard_host=""
CONFIG_thingsboard_token=""
CONFIG_thingsboard_code=0
CONFIG_thingsboard_code_OK=200
CONFIG_icse_file=""	# Device file of the relay board
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
$(process_help -b)
  -1 pretend (force) correct connection
  -2 pretend (force) failed connection

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
	if [[ "${CONFIG_inet_status}" == "${CONFIG_idle}" ]]
	then
		set | grep "^LOG_" > "${CONFIG_log_file}"
	elif [[ -f "${CONFIG_log_file}" ]]
	then
		rm "${CONFIG_log_file}"
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

# @info:  Checking internet connection
# @args:  none
# @return: global config variable
# @deps:  Overloaded library function
check_inet () {
	msg="Checking internet connection status"
	echo_text -hp -${CONST_level_verbose_info} "${msg}$(force_token) ... "
	# Dry run simulation
	if [[ ${CONFIG_flag_force_inet} -eq 1 ]]
	then
		CONFIG_inet_status=${CONFIG_active}
	elif [[ ${CONFIG_flag_force_idle} -eq 1 ]]
	then
		CONFIG_inet_status=${CONFIG_idle}
	# Check connection to internet
	else
		TestIP=${CONFIG_inet_ip}
		if [ -n "${TestIP}" ]
		then
			ping -c1 -w5 ${TestIP} >/dev/null
			if [ $? -eq 0 ]
			then
				CONFIG_inet_status=${CONFIG_active}
			else
				CONFIG_inet_status=${CONFIG_idle}
			fi
		fi
	fi
	echo_text -${CONST_level_verbose_info} "${CONFIG_inet_status}."
	if [ -n "${CONFIG_status}" ]
	then
		echo_text -ISL -${CONST_level_verbose_none} "${msg} ... ${CONFIG_inet_status}." >> "${CONFIG_status}"
	fi
}

# @info: Toggle relay
# @return: LOG_* variables
# @deps: CONFIG_* variables
relay_toggle () {
	msg="Toggling relay '${CONFIG_icse_file}'"
	sep=" ... "
	echo_text -hp -${CONST_level_verbose_info} "${msg}$(dryrun_token)"
	if [[ "${LOG_relay}" == "${CONFIG_active}" ]]
	then
		# Control both relays on the board at once
		control_byte="03"
		LOG_relay=${CONFIG_idle}
	else
		control_byte="00"
		LOG_relay=${CONFIG_active}
	fi
	if [[ $CONFIG_flag_dryrun -eq 0 ]]
	then
		echo "${control_byte}" | xxd -r -p > ${CONFIG_icse_file}
	fi
	result="${sep}to ${LOG_relay} by ${control_byte}."
	echo_text -${CONST_level_verbose_info} "${result}"
	LOG_period=${CONFIG_log_count}
	LOG_toggle=1
	if [ -n "${CONFIG_status}" ]
	then
		echo_text -ISL -${CONST_level_verbose_none} "${msg}${result}" >> "${CONFIG_status}"
	fi
}

# @info: Toggle relay
# @return: LOG_* variables
# @deps: CONFIG_* variables
relay_control () {
	if [[ "${CONFIG_inet_status}" == "${CONFIG_idle}" ]]
	then
		((LOG_period--))
		echo_text -h -${CONST_level_verbose_info} "Countdown ... Inet ${CONFIG_inet_status}, Relay ${LOG_relay}, Period ${LOG_period}"
		if [[ ${LOG_period} -le 0 ]]
		then
			relay_toggle
		fi
	fi
}

# @info:  Send data to ThingsBoard IoT platform
# @args:  none
# @return: global CONFIG_thingsboard_code variable
# @deps:  global CONFIG_mains variables
write_thingsboard () {
	local reqdata inet relay
	# Compose data item for internet connection status
	if [[ "${CONFIG_inet_status}" == "${CONFIG_active}" ]]
	then
		inet="true"
	elif [[ "${CONFIG_inet_status}" == "${CONFIG_idle}" ]]
	then
		inet="false"
	else
		inet=""
	fi
	if [ -n "${inet}" ]
	then
		reqdata="${reqdata}\"inetConnect\":${inet},"
	fi
	# Compose data item for relay toggling
	if [[ ${LOG_toggle} -eq 1 ]]
	then
		if [[ "${LOG_relay}" == "${CONFIG_active}" ]]
		then
			relay="true"
		elif [[ "${LOG_relay}" == "${CONFIG_idle}" ]]
		then
			relay="false"
		else
			relay=""
		fi
		LOG_toggle=0
	fi
	if [ -n "${relay}" ]
	then
		reqdata="${reqdata}\"inetRelay\":${relay},"
	fi
	# Process request payload
	msg="Sending to ThingsBoard"
	sep=" ... "
	if [ -n "${reqdata}" ]
	then
		reqdata=${reqdata::-1}
		reqdata="{${reqdata}}" # Create JSON object
	else
		echo_text -${CONST_level_verbose_info} "${msg}${sep}no payload. Exiting."
		fatal_error "${msg} failed with no payload."
	fi
	# Compose HTTP request
	echo_text -hp -${CONST_level_verbose_info} "${msg}$(dryrun_token)${sep}${reqdata}"
	if [[ $CONFIG_flag_dryrun -eq 0 && -n "${reqdata}" ]]
	then
		CONFIG_thingsboard_code=$(curl --location --silent \
--write-out %{http_code} \
--output /dev/null \
--connect-timeout 3 \
--request POST "${CONFIG_thingsboard_host}/api/v1/${CONFIG_thingsboard_token}/telemetry" \
--header "Content-Type: application/json" \
--data-raw "${reqdata}")
	else
		CONFIG_thingsboard_code=${CONFIG_thingsboard_code_OK}
	fi
	result="HTTP status code ${CONFIG_thingsboard_code}"
	if [[ ${CONFIG_thingsboard_code} -ne ${CONFIG_thingsboard_code_OK} ]]
	then
		echo_text -${CONST_level_verbose_info} "${sep}failed with ${result}. Exiting."
		fatal_error "${msg} failed with ${result}."
	else
		echo_text -${CONST_level_verbose_info} "${sep}${CONFIG_thingsboard_code}."
	fi
	if [ -n "${CONFIG_status}" ]
	then
		echo_text -ISL -${CONST_level_verbose_none} "${msg}${sep}${result}." >> "${CONFIG_status}"
	fi
}
# <- END _functions


# Process command line parameters
process_options $@
while getopts "${LIB_options}12" opt
do
	case "$opt" in
	1)
		CONFIG_flag_force_inet=1
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

if [ -n "${CONFIG_status}" ]
then
	echo_text -s -${CONST_level_verbose_info} "Writing to status file ... '${CONFIG_status}'."
	echo "" > "${CONFIG_status}"
fi

check_inet
relay_control
write_thingsboard

# End of script processed by TRAP
