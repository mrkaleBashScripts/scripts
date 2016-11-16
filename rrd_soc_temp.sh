#!/usr/bin/env bash
#
# NAME:
#   rrd_soc_temp.sh - Record system temperature to Round Robin Database
#
# SYNOPSIS:
#   rd_soc_temp.sh [OPTION [ARG]] [RRD_file]
#
# DESCRIPTION:
# Script measures internal temperature of the CPU and stores it into RRD.
# - Script has to be run under root privileges (sudo ...).
# - Script is supposed to run under cron.
# - Script logs to "user.log".
# - Script may write its working status into a status (tick) file if defined, what may
#   be considered as a monitoring heartbeat of the script especially then in normal conditions
#   it produces no output.
# - Status file should be located in the temporary file system (e.g., in the folder /run)
#   in order to reduce writes to the SD card.
# - All essential parameters are defined in the section of configuration parameters.
#   Their description is provided locally. Script can be configured by changing values of them.
# - Configuration parameters in the script can be overriden by the corresponding ones
#   in a configuration file declared in the command line.
# - If RRD file does not exist yet, the script creates one.
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
CONFIG_copyright="(c) 2016 Libor Gabaj <libor.gabaj@gmail.com>"
CONFIG_version="0.1.0"
CONFIG_commands=('rrdtool awk') # List of general commands
CONFIG_commands_run=('') # List of commands for full running
#
CONFIG_flag_print_temp=0	# List sensor parameters flag
CONFIG_rrd_file="${CONFIG_script%\.*}.rrd"	# Round Robin Database file
CONFIG_rrd_step=300	# Round Robin Database base data feeding interval
CONFIG_rrd_hartbeat=2	# Round Robin Database hartbeat interval as a multiplier of the step
# <- END _config

# -> BEGIN _functions

# @info:	Display usage description
# @args:	(none)
# @return:	(none)
# @deps:	(none)
show_help () {
	echo
	echo "${CONFIG_script} [OPTION [ARG]] [RRD_file]"
	echo "
Record internal temperature into the Round Robin Database. Default RRD is
'$(basename ${CONFIG_script} .sh).rrd' in the folder of the script.
$(process_help -o)
  -T			Temperature: Display current SoC temperature
$(process_help -f)
"
}

# @info:	Read SoC temperature in milidegrees Celsius
# @args:	none
# @return:	System temperature
# @deps:	none
read_soc () {
	local temp
	temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
	printf "$temp"
}

# @info:	Create RRD file
# DS: System temperature in milidegrees Celsius
# RRA:
#	Read values for last 6 hours
#	Hour averages for last 7 days
#	Qoarter averages for last 30 days
#	Daily maximals for last 7 days
#	Daily maximals for last 30 days
#	Daily maximals for last 180 days
#	Daily minimals for last 7 days
#	Daily minimals for last 30 days
#	Daily minimals for last 180 days
# @args:	none
# @return:	none
# @deps:	none
create_rrd_file () {
	local dslist
	echo_text -h -$CONST_level_verbose_function "Creating RRD file '${CONFIG_rrd_file}' with data stream$(dryrun_token):"
	dslist="DS:temp:GAUGE:$(( ${CONFIG_rrd_step} * ${CONFIG_rrd_hartbeat} )):0:85000"
	echo_text -s -$CONST_level_verbose_function "${dslist}"
	# Create RRD
	if [[ $CONFIG_flag_dryrun -eq 0 ]]
	then
		rrdtool create "${CONFIG_rrd_file}" \
		--step ${CONFIG_rrd_step} \
		--start -${CONFIG_rrd_step} \
		${dslist} \
		RRA:AVERAGE:0.5:1:72 \
		RRA:AVERAGE:0.5:12:168 \
		RRA:AVERAGE:0.5:72:120 \
		RRA:MAX:0.5:288:7 \
		RRA:MAX:0.5:288:30 \
		RRA:MAX:0.5:288:180 \
		RRA:MIN:0.5:288:7 \
		RRA:MIN:0.5:288:30 \
		RRA:MIN:0.5:288:180
	fi
}
# <- END _functions

# Process command line parameters
process_options $@
while getopts "${LIB_options}T" opt
do
	case "$opt" in
	T)
		CONFIG_flag_print_temp=1
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
if [ -n "$1" ]
then
	CONFIG_rrd_file="$1"
fi
init_script
process_folder -t "Status" -f "${CONFIG_status}"
process_folder -t "RRD" -fce "${CONFIG_rrd_file}"
show_configs

# -> Script execution
trap stop_script EXIT

# Read system temperature in milidegrees Celsius
SOC_temp=$(read_soc)

# Create RRD
if [ ! -f "$CONFIG_rrd_file" ]
then
	echo_text -h -$CONST_level_verbose_info "RRD file '$CONFIG_rrd_file' does not exist. Creating$(dryrun_token)."
	create_rrd_file
fi

# Write temperature into RRD
RRDcmd="rrdtool update ${CONFIG_rrd_file} N:${SOC_temp:-U}"
echo_text -h -$CONST_level_verbose_info "RRD command for storing temperature in millidegrees Celsius$(dryrun_token):"
echo_text -s  -$CONST_level_verbose_info "$RRDcmd"
if [[ $CONFIG_flag_dryrun -eq 0 ]]
then
	$($RRDcmd)
fi
RESULT=$?
if [ $RESULT -ne 0 ]
then
	msg="RRD update failed with error code '$RESULT'."
	echo_text -e  -$CONST_level_verbose_error "$msg"
	log_text  -ES -$CONST_level_logging_error "$msg"
fi

# Print sensor parameters
if [[ $CONFIG_flag_print_temp -eq 1 ]]
then
	echo_text -hb -$CONST_level_verbose_none "System temperature =  $(echo ${SOC_temp} | awk '{print($1/1e3)}')'C"
fi

# End of script processed by TRAP
