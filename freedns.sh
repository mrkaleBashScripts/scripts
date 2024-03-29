#!/usr/bin/env bash
#
# NAME:
#   freedns.sh - Update public IP address at FreeDNS service (https://freedns.afraid.org/)
#
# SYNOPSIS:
#   freedns.sh [OPTION [ARG]]
#
# DESCRIPTION:
# Script sends appropriate HTTP request to FreeDNS service in order to update
# dynamic DNS web address of the current computer.
# - Script has to be run under root privileges (sudo ...).
# - Script is supposed to run under cron.
# - All essential parameters are defined in the section of configuration parameters.
#   Their description is provided locally. Script can be configured by changing values of them.
# - Configuration parameters in the script can be overriden by the corresponding ones
#   in a configuration file or credentials file declared in the command line.
#
# OPTIONS:
#   -h  Help
#       Show usage description and exit.
#
#   -s  Simmulation
#       Perform dry run without sending to FreeDNS.
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
#   -t  StatusFile
#       Tick file for writing working status of the script.
#       Should be located in temporary file system.
#
#   -1  Force success IP update
#
#   -2  Force failed IP update
#
# LICENSE:
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#

# Load library file
LIB_options_exclude=('p')
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
CONFIG_commands_run=('curl') # List of commands for full running
CONFIG_flag_root=1	# Check root privileges flag
CONFIG_flag_force_success=0
CONFIG_flag_force_failure=0
CONFIG_status="/tmp/${CONFIG_script}.inf"  # Status file
CONFIG_freedns_host="sync.afraid.org/u"
CONFIG_freedns_token=""
CONFIG_freedns_code_OK=200
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
Update IP address at FreeDNS service.
$(process_help -o)
  -1 pretend (force) successful IP update
  -2 pretend (force) failed IP update
$(process_help -f)
"
}

# @info: Actions at finishing script invoked by 'trap'
# @args: none
# @return: none
# @deps: Overloaded library function
stop_script () {
	show_manifest STOP
}

# @info:  Send request to FreeDNS
# @args:  none
# @return: none
# @deps:  none
write_freedns () {
  local msg resp output
  msg="HTTP request to FreeDNS"
	echo_text -hp -${CONST_level_verbose_info} "${msg}$(dryrun_token)$(force_token)${sep}"
	# Dry run simulation
	if [[ ${CONFIG_flag_force_success} -eq 1 || ${CONFIG_flag_dryrun} -eq 1 ]]
	then
		resp=${CONFIG_freedns_code_OK}
	elif [[ ${CONFIG_flag_force_failure} -eq 1 ]]
	then
		resp=000
	else
		# Compose and send HTTP request
		resp=$(curl --silent \
--write-out %{response_code} \
--output "${CONFIG_status}" \
--request GET "${CONFIG_freedns_host}/${CONFIG_freedns_token}/" \
)
	fi
	result="HTTP status code ${resp}"
	if [[ ${resp} -ne ${CONFIG_freedns_code_OK} ]]
	then
		echo_text -${CONST_level_verbose_info} "failed with ${result}. Exiting."
		status_text -aF "${msg}${sep}${result}"
		fatal_error -s "${msg} failed with ${result}."
	else
		echo_text -${CONST_level_verbose_info} "${resp}."
		status_text -a "${msg}${sep}${result}"
		log_text -IS "${msg}${sep}${result}"
	fi
}
# <- END _functions

# Process command line parameters
process_options $@
while getopts "${LIB_options}12" opt
do
	case "$opt" in
	1)
		CONFIG_flag_force_success=1
		CONFIG_flag_force=1
		;;
	2)
		CONFIG_flag_force_failure=1
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

status_text
write_freedns

# End of script processed by TRAP
