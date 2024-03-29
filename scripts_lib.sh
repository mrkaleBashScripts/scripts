#!/usr/bin/env bash
#
# NAME:
#   scripts_lib.sh - Library of shared functions and variables for scripts
#
# SYNOPSIS:
#   source scripts_lib.sh
#
# DESCRIPTION:
# Script is used as one place for shared functions and variables including configuration ones
# for production scripts. Those utility functions are maintained at one place for all scripts.
#
# - Some predefined command line options can be forbidden by enumerating them
#   in the array 'LIB_options_exclude' one by one.
#
# LICENSE:
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#

# Extend search path with system binaries folder if needed
if [[ ":$PATH:" != *":/sbin:"* ]]
then
  PATH=/sbin:${PATH}
fi

# -> BEGIN Library configs
LIB_copyright="(c) 2014-2021 Libor Gabaj <libor.gabaj@gmail.com>"
LIB_script=$(basename $0)
LIB_version="0.13.2"
# Process default options
# LIB_options_exclude=('t' 'l') # List of omitted options at the very begining of script
LIB_options=":hsVcmvo:l:f:t:"
for opt in ${LIB_options_exclude[@]}
do
  LIB_options=${LIB_options//$opt:}
  LIB_options=${LIB_options//$opt}
done
# <- END Library configs

# -> BEGIN Common working configs
CONFIG_copyright="(c) $(date +%Y)"
CONFIG_script=$(basename $0)
CONFIG_commands_common=('basename' 'dirname' 'hostname' 'date' 'logger' 'whoami' 'id' 'tr' 'sleep') # Common system utility
CONFIG_commands=() # Array of generally needed commands
CONFIG_commands_run=() # List of commands for full running
CONFIG_commands_dryrun=() # Array of commands for dry running
CONFIG_level_logging=1  # Level of logging to system log - 0=none, 1=error, 2=warning, 3=info, 4=full
CONFIG_level_verbose=1  # Level of verbosity to console - 0=none, 1=error, 2=mail, 3=info, 4=function, 5=full
CONFIG_flag_print_configs=0 # List configuration parameters flag
CONFIG_flag_dryrun=0  # Simulation mode flag
CONFIG_flag_force=0  # Force mode flag
CONFIG_flag_root=0  # Check root privileges flag
CONFIG_config=""  # Configuration file
CONFIG_credentials=""  # Credentials file
CONFIG_status=""  # Status file
CONFIG_thingsboard_host=""
CONFIG_thingsboard_token=""
CONFIG_thingsboard_fail_count=4 # HTTP request retries
CONFIG_thingsboard_fail_delay=15 # Retry seconds for another HTTP request
CONFIG_thingsboard_code_OK=200
# <- END Common working configs

# <- BEGIN _constants
CONST_level_logging_none=0
CONST_level_logging_error=1
CONST_level_logging_warn=2
CONST_level_logging_info=3
CONST_level_logging_full=4
CONST_level_logging_min=${CONST_level_logging_none}
CONST_level_logging_max=${CONST_level_logging_full}
CONST_level_logging_dft=${CONFIG_level_logging}

CONST_level_verbose_none=0
CONST_level_verbose_error=1
CONST_level_verbose_mail=2
CONST_level_verbose_info=3
CONST_level_verbose_function=4
CONST_level_verbose_full=5
CONST_level_verbose_min=${CONST_level_verbose_none}
CONST_level_verbose_max=${CONST_level_verbose_full}
CONST_level_verbose_dft=${CONFIG_level_verbose}

sep=" ... "
# <- END _constants


# -> BEGIN _functions

# @info:  Checks if a folder is writable by creating a temporary file in it and removing it afterwards.
# @args:  folder to test
# @return:  returns false if creation of temporary file failed or it can't be removed afterwards; else true
# @deps:  none
chk_folder_writable () {
  local temp
  temp="$(mktemp "$1"/tmp.XXXXXX 2>/dev/null)"
  if (( $? == 0 ))
  then
    rm "${temp}" &>/dev/null || return 1
    return 0
  else
    return 1
  fi
}

# @info:  Compose prefix string.
# @opts:
#    -S ... separator
#    -T ... terminator
#    -I ... word for info
#    -W ... word for warning
#    -E ... word for error
#    -F ... word for fatal
#    -D ... date
#    -H ... hostname
#    -V ... script version
#    -L ... log record
#    -N ... logger name tag
# @args:  none
# @return:  none
# @deps:  none
prefix_token () {
  local OPTIND opt
  local prefix="" tag
  while getopts ":STIWEFDHVLN" opt
  do
    case "$opt" in
    S)
      prefix+=' -- '
      ;;
    T)
      prefix+=': '
      ;;
    I)
      prefix+='INFO'
      ;;
    W)
      prefix+='WARNING'
      ;;
    E)
      prefix+='ERROR'
      ;;
    F)
      prefix+='FATAL'
      ;;
    D)
      prefix+="$(date +'%F %T')"
      ;;
    H)
      prefix+="$(hostname)"
      ;;
    V)
      prefix+="${CONFIG_script} ${CONFIG_version}"
      ;;
    L)
      prefix+="$(${FUNCNAME[0]} -DSVSHT)"
      ;;
    N)
      tag="${CONFIG_script%\.*}"
      tag="${tag^^*} ${CONFIG_version}"
      prefix+="$tag"
      ;;
    esac
  done
  printf "${prefix}"
}

# @info:  Print input arguments with new line at the end.
# @opts:
#    -S ... separator
#    -I ... word for info
#    -W ... word for warning
#    -E ... word for error
#    -F ... word for fatal
#    -L ... log record
#    -h ... insert hash prefix at the very beginning of the text
#    -f ... insert function prefix at the very beginning of the text
#    -s ... insert space prefix at the very beginning of the text
#    -w ... insert warning prefix at the very beginning of the text
#    -e ... write as error to standard error output
#    -x ... write as fatal to standard error output
#    -p ... use printf instead of echo, i.e., do not use new-line
#    -b ... print blank line before message
#    -a ... print blank line after message
#    -0 ~ -9 ... output according to verbose level
# @args:  Arguments to echo
# @return:  none
# @deps:  none
echo_text () {
  local OPTIND opt
  local prefix=""
  local redir=0 before=0 after=0 print=0
  local level=${CONST_level_verbose_dft}
  while getopts ":SIWEFLhfswexpba012345" opt
  do
    case "$opt" in
    S|I|W|E|F|L)
      prefix+=$(prefix_token -$opt)
      ;;
    h)
      prefix+='# '
      ;;
    f)
      prefix+='### '
      ;;
    s)
      prefix+='  '
      ;;
    w)
      prefix+='!!! '
      ;;
    e)
      prefix+="$(echo_text -wp)$(prefix_token -ESL)"
      redir=1
      ;;
    x)
      prefix+="$(echo_text -wp)$(prefix_token -FSL)"
      redir=1
      ;;
    p)
      print=1
      ;;
    b)
      before=1
      ;;
    a)
      after=1
      ;;
    0|1|2|3|4|5)
      level=$opt
      ;;
    esac
  done
  if [[ ${CONFIG_level_verbose} -ge $level ]]
  then
    shift $(($OPTIND-1))
    if [[ $before -eq 1 ]]
    then
      if [[ $redir -eq 1 ]]
      then
        echo >&2 1>&2
      else
        echo
      fi
    fi
    if [[ $redir -eq 1 ]]
    then
      printf "${prefix}$@" >&2 1>&2 2>/dev/null
    else
      printf "${prefix}$@" 2>/dev/null
    fi
    if [[ $print -eq 0 ]]
    then
      if [[ $redir -eq 1 ]]
      then
        echo >&2 1>&2
      else
        echo
      fi
    fi
    if [[ $after -eq 1 ]]
    then
      if [[ $redir -eq 1 ]]
      then
        echo >&2 1>&2
      else
        echo
      fi
    fi
  fi
}

# @info:  Log text to syslog
# @opts:
#    -S|I|W|E|F ... prefixes
#    -0 ~ -9 ... Logging levels
# @return:  none
# @deps:  none
log_text () {
  local OPTIND opt
  local prefix=""
  local level=${CONST_level_logging_dft}
  while getopts ":SIWEF01234" opt
  do
    case "$opt" in
    S|I|W|E|F)
      prefix+=$(prefix_token -$opt)
      ;;
    0|1|2|3|4)
      level=$opt
      ;;
    esac
  done
  if [[ ${CONFIG_level_logging} -ge ${level} ]]
  then
    shift $(($OPTIND-1))
    echo_text -f -${CONST_level_verbose_function} "Logging to syslog ... $(prefix_token -N)::$prefix$@"
    logger -t "$(prefix_token -N)" "$prefix$@"
  fi
}

# @info:  Write text to status file
# @desc:  If there no input text and no append option, the status file is just
#         deleted.
# @opts:
#    $1 ... Message for status file
#    -a ... Append input message to the status file
#    -I ... Prepend prefix for info to the input message (default)
#    -W ... Prepend prefix for warning to the input message
#    -E ... Prepend prefix for error to the input message
#    -F ... Prepend prefix for fatal to the input message
# @return:  none
# @deps:  none
status_text () {
  local OPTIND opt msg
  local flag_append=0
  local pfx="I"
  while getopts ":aIWEF" opt
  do
    case "$opt" in
    a)
      flag_append=1
      ;;
    I|W|E|F)
      pfx=$opt
      ;;
    esac
  done
  if [ -n "${CONFIG_status}" ]
  then
    shift $(($OPTIND-1))
    msg="$1"
    echo_text -f -${CONST_level_verbose_function} "Writing to status file '${CONFIG_status}'${sep}${msg}"
    if [[ $flag_append -eq 0 && -f "${CONFIG_status}" ]]
    then
      rm "${CONFIG_status}" >/dev/null
    fi
    if [ -n "${msg}" ]
    then
      echo_text -${pfx}SL -${CONST_level_verbose_none} "${msg}" >> "${CONFIG_status}"
    fi
  fi
}

# @info:  Print error text to standard error output, log it to syslog and exit script
# @opts:
#    -s ... Silent. Do not echo text and retun zero exit code, just log.
# @return:  exit 1
# @deps:  echo_text, log_text
fatal_error () {
  local OPTIND opt
  local flag_silent=0
  while getopts ":s" opt
  do
    case "$opt" in
    s)
      flag_silent=1
      ;;
    esac
  done
  log_text -FS -${CONST_level_logging_error} "$@"
  if [[ $flag_silent -eq 0 ]]
  then
    echo_text -x -${CONST_level_verbose_error} "$@"
    exit 1
  else
    exit 0
  fi
}

# @info:  Display configuration parameters
# @args:  none
# @return:  List of configuration parameters
# @deps:  none
show_configs () {
  local cfgArray
  if [[ $CONFIG_flag_print_configs -eq 1 ]]
  then
    echo_text -hb -${CONST_level_verbose_none} "List of configuration parameters:"
    for prm in ${!CONFIG_@}
    do
      cfgArray=$(declare -p $prm 2>/dev/null | grep -i 'declare \-a')
      if [ $? -eq 0 ]
      then
        echo_text -s -${CONST_level_verbose_none} "${cfgArray:11}"
      else
        if [ -z "${!prm}" ]
        then
          echo_text -s -${CONST_level_verbose_none} "${prm} = <null>"
        else
          echo_text -s -${CONST_level_verbose_none} "${prm} = %s" "${!prm}"
        fi
      fi
    done
    echo_text -${CONST_level_verbose_none}
  fi
}

# @info:  Check logging levels
# @args:  none
# @return:  none
# @deps:  none
check_level_loging () {
  if [[ $CONFIG_level_logging -lt $CONST_level_logging_min ]]
  then
    CONFIG_level_logging=$CONST_level_logging_min
  fi
  if [[ $CONFIG_level_logging -gt $CONST_level_logging_max ]]
  then
    CONFIG_level_logging=$CONST_level_logging_max
  fi
  case "$CONFIG_level_logging" in
  0|1|2|3|4)
    ;;
  *)
    CONFIG_level_logging=$CONST_level_logging_dft
    ;;
  esac
}

# @info:  Check verbose levels
# @args:  none
# @return:  none
# @deps:  none
check_level_verbose () {
  if [[ ${CONFIG_level_verbose} -lt ${CONST_level_verbose_min} ]]
  then
    CONFIG_level_verbose=${CONST_level_verbose_min}
  fi
  if [[ ${CONFIG_level_verbose} -gt ${CONST_level_verbose_max} ]]
  then
    CONFIG_level_verbose=${CONST_level_verbose_max}
  fi
  case "${CONFIG_level_verbose}" in
  0|1|2|3|4|5)
    ;;
  *)
    CONFIG_level_verbose=${CONST_level_verbose_dft}
    ;;
  esac
}

# @info:  Compose dryrun token.
# @args:  none
# @return:  Dryrun string token
# @deps:  none
dryrun_token () {
  local msg_dryrun
  if [[ ${CONFIG_flag_dryrun} -eq 1 ]]
  then
    msg_dryrun=" ... dryrun"
  else
    msg_dryrun=""
  fi
  printf "${msg_dryrun}"
}

# @info:   Compose force token.
# @args:   none
# @return: Force string token
# @deps:   none
force_token () {
  local msg_force
  if [[ $CONFIG_flag_force -eq 1 ]]
  then
    msg_force=" ... force"
  else
    msg_force=""
  fi
  printf "${msg_force}"
}

# @info:  Convert seconds to days and time
# @args:  Seconds
# @return:  Time string
# @deps:  none
seconds2time () {
  local secs=$1 days=0 timestring=""
  days=$((secs/86400))
  if [ $days -gt 0 ]
  then
    timestring+="${days}d "
  fi
  timestring+=$(date -ud @${secs} +"%H:%M:%S")
  printf "$timestring"
}

# @info:  Check presence of needed commands
# @args:  none
# @return:  message or fatal error
# @deps:  CONFIG_commands, CONFIG_commands_dryrun, CONFIG_commands_run
check_commands () {
  local cmd_list="" bad_commands=""
  # Process commands
  echo_text -hp -${CONST_level_verbose_info} "Checking expected commands$(dryrun_token) ... "
  cmd_list=${CONFIG_commands_common[@]}
  cmd_list+=" ${CONFIG_commands[@]}"
  if [ ${CONFIG_flag_dryrun} -eq 1 ]
  then
    cmd_list+=" ${CONFIG_commands_dryrun[@]}"
  else
    cmd_list+=" ${CONFIG_commands_run[@]}"
  fi
  # Detect not available commands
  for command in ${cmd_list}
  do
    if ( ! command -v ${command} >/dev/null )
    then
      bad_commands+=" ${command}"
    fi
  done
  if [ -n "${bad_commands}" ]
  then
    echo_text -${CONST_level_verbose_info} "not available ...${bad_commands} ... failed. Exiting."
    fatal_error "Command(s)${bad_commands} not available."
  else
    echo_text -${CONST_level_verbose_info} "all available ... success. Proceeding."
  fi
}

# @info:  Check root privilegies
# @args:  none
# @return:  message or fatal error
# @deps:  none
check_root () {
  if [ $CONFIG_flag_root -eq 1 ]
  then
    echo_text -hp -${CONST_level_verbose_info} "Checking script privilegies$(dryrun_token) ... "
    if [[ ${CONFIG_flag_dryrun} -eq 1 || $(id -u) -eq 0 ]]
    then
      echo_text -${CONST_level_verbose_info} "ok ... $(whoami). Proceeding."
    else
      echo_text -${CONST_level_verbose_info} "has to be run as root. Exiting."
      fatal_error "Script is not run as root."
    fi
  fi
}

# @info:  Process config file
# @args:  none
# @return:  message or fatal error
# @deps:  none
process_config () {
  if [ -n "${CONFIG_config}" ]
  then
    echo_text -hp -${CONST_level_verbose_info} "Checking configuration file '${CONFIG_config}' ... "
    if [ -f "${CONFIG_config}" ]
    then
      if [ -s "${CONFIG_config}" ]
      then
        source "${CONFIG_config}"
        echo_text -${CONST_level_verbose_info} "exists and is not empty. Applying."
      else
        echo_text -${CONST_level_verbose_info} "is empty. Ignoring."
      fi
    else
      echo_text -${CONST_level_verbose_info} "does not exist. Exiting."
      fatal_error "Configuraton file '${CONFIG_config}' does not exist."
    fi
  fi
}

# @info:  Process credentials file
# @args:  none
# @return:  message or fatal error
# @deps:  none
process_credentials () {
  if [ -n "${CONFIG_credentials}" ]
  then
    echo_text -hp -${CONST_level_verbose_info} "Checking credentials file '${CONFIG_credentials}' ... "
    if [ -f "${CONFIG_credentials}" ]
    then
      if [ -s "${CONFIG_credentials}" ]
      then
        source "${CONFIG_credentials}"
        echo_text -${CONST_level_verbose_info} "exists and is not empty. Applying."
      else
        echo_text -${CONST_level_verbose_info} "is empty. Ignoring."
      fi
    else
      echo_text -${CONST_level_verbose_info} "does not exist. Exiting."
      fatal_error "Credentials file '${CONFIG_credentials}' does not exist."
    fi
  fi
}

# @info:  Check folder for writing to or create it
# @opts:
#    -t Title ... descriptive name of a folder
#    -f ... input folder is file
#    -c ... create input folder if it does not exist
#    -e ... fatal error if input folder not declared
#    -x ... fatal error if input folder or file does not exist
# @args:  folder or file
# @return:  message or fatal error
# @deps:  none
process_folder () {
  local folder title="Regular" object
  local isFile=0 isCreate=0 isError=0 isExist=0
  local OPTIND opt
  # Process input parameters
  while getopts ":t:fcex" opt
  do
    case "$opt" in
    t)
      title="$OPTARG"
      ;;
    f)
      isFile=1
      ;;
    c)
      isCreate=1
      ;;
    e)
      isError=1
      ;;
    x)
      isExist=1
      ;;
    esac
  done
  shift $(($OPTIND-1))
  # Detect input parameter
  object="folder"
  if [ $isFile -eq 1 ]
  then
    object="file"
  fi
  # Check input parameter
  if [ -z "$1" ]
  then
    if [ $isError -eq 1 ]
    then
      echo_text -h -${CONST_level_verbose_info} "${title} ${object} declared neither in command line nor configuration file. Exiting."
      fatal_error "${title} ${object} not declared."
    else
      return 0
    fi
  fi
  folder="$1"
  # Separate folder from file
  if [ $isFile -eq 1 -a $isExist -eq 0 ]
  then
    folder="$(dirname "${folder}")"
  fi
  # Check folder permission
  if [ $isExist -eq 0 ]
  then
    echo_text -hp -${CONST_level_verbose_info} "Checking ${title} folder '${folder}' ... "
    if [[ "${folder}" == *@*:* ]]
    then
      echo_text -${CONST_level_verbose_info} "remote. Proceeding."
    elif [ -d "${folder}" ]
    then
      echo_text -p -${CONST_level_verbose_info} "exists ... "
      if chk_folder_writable "${folder}"
      then
        echo_text -${CONST_level_verbose_info} "writable. Proceeding."
      elif [ ${CONFIG_flag_dryrun} -eq 1 ]
      then
        echo_text -${CONST_level_verbose_info} "unwritable. Proceeding$(dryrun_token)."
      else
        echo_text -${CONST_level_verbose_info} "unwritable. Exiting."
        fatal_error "${title} folder '${folder}' is unwritable."
      fi
    elif [ -f "${folder}" ]
    then
      echo_text -${CONST_level_verbose_info} "is a file. Exiting."
      fatal_error "${title} folder '${folder}' is a file."
    else
      echo_text -${CONST_level_verbose_info} "does not exist. "
      if [ $isCreate -eq 0 ]
      then
        echo_text -${CONST_level_verbose_info} "Exiting."
        fatal_error "${title} folder '${folder}' does not exist."
      else
        # Create folder
        echo_text -p -${CONST_level_verbose_info} "Creating ... "
        if mkdir -p "${folder}" >/dev/null 2>&1
        then
          echo_text -${CONST_level_verbose_info} "success. Proceeding."
        else
          echo_text -${CONST_level_verbose_info} "failed. Exiting."
          fatal_error "${title} folder '${folder}' cannot be created."
        fi
      fi
    fi
  else
    echo_text -hp -${CONST_level_verbose_info} "Checking ${title} ${object} '${folder}' ... "
    if [ \( $isFile -eq 1 -a -f "${folder}" \) -o \( $isFile -eq 0 -a -d "${folder}" \) ]
    then
      echo_text -${CONST_level_verbose_info} "exists. Proceeding."
    else
      echo_text -${CONST_level_verbose_info} "missing. Exiting."
      fatal_error "${title} ${object} '${folder}' does not exist."
    fi
  fi
}

# @info:  Process common options
# @args:  none
# @return:  none
# @deps:  none
help="See help by '${CONFIG_script} -h' please!"
process_options () {
  local OPTIND opt
  while getopts "${LIB_options}" opt
  do
    case "$opt" in
    h)
      show_help
      exit
      ;;
    s)
      CONFIG_flag_dryrun=1
      ;;
    V)
      echo_text -h "${CONFIG_script} ${CONFIG_version} - ${CONFIG_copyright}"
      exit
      ;;
    c)
      CONFIG_flag_print_configs=1
      ;;
    m)
      CONFIG_level_verbose=${CONST_level_verbose_mail}
      ;;
    v)
      CONFIG_level_verbose=${CONST_level_verbose_max}
      ;;
    f)
      CONFIG_config=$OPTARG
      ;;
    p)
      CONFIG_credentials=$OPTARG
      ;;
    o)
      case "$OPTARG" in
      0|1|2|3|4|5)
        ;;
      *)
        msg="Unknown verbose level '$OPTARG'."
        fatal_error "$msg $help"
        ;;
      esac
      CONFIG_level_verbose=$OPTARG
      ;;
    l)
      case "$OPTARG" in
      0|1|2|3|4)
        ;;
      *)
        msg="Unknown logging level '$OPTARG'."
        fatal_error "$msg $help"
        ;;
      esac
      CONFIG_level_logging=$OPTARG
      ;;
    t)
      CONFIG_status=$OPTARG
      ;;
    :)
      case "$OPTARG" in
      o)
        msg="Missing verbose level for option '-$OPTARG'."
        ;;
      l)
        msg="Missing logging level for option '-$OPTARG'."
        ;;
      f)
        msg="Missing configuration file for option '-$OPTARG'."
        ;;
      p)
        msg="Missing credentials file for option '-$OPTARG'."
        ;;
      t)
        msg="Missing status (tick) file for option '-$OPTARG'."
        ;;
      esac
      fatal_error "$msg $help"
    esac
  done
}

# @info:  Create common help texts. Unwished options put to array in 'LIB_options_exclude'
# @opts:
#    -o ... text for options
#    -f ... text for footer
# @args:  none
# @return:  text for help
# @deps:  none
process_help () {
  local help
  local OPTIND opt
  # Process input parameters
  while getopts ":bof" opt
  do
    case "$opt" in
    o)
      help="
Options and arguments:
"
      if [[ $LIB_options == *h* ]]
      then
        help+="
  -h help: show this help and exit"
      fi
      if [[ $LIB_options == *V* ]]
      then
        help+="
  -V Version: show version information and exit"
      fi
      if [[ $LIB_options == *c* ]]
      then
        help+="
  -c configs: print listing of all configuration parameters"
      fi
      if [[ $LIB_options == *o* ]]
      then
        help+="
  -o output_level
     level of verbosity
     0=none, 1=errors, 2=mails, 3=info, 4=functions, 5=full (default ${CONFIG_level_verbose})"
      fi
      if [[ $LIB_options == *m* ]]
      then
        help+="
  -m mailing: display all processing messages; alias for '-o${CONST_level_verbose_mail}'"
      fi
      if [[ $LIB_options == *v* ]]
      then
        help+="
  -v verbose: display all processing messages; alias for '-o${CONST_level_verbose_max}'"
      fi
      if [[ $LIB_options == *l* ]]
      then
        help+="  -l log_level
     logging: level of logging intensity to syslog
     0=none, 1=errors, 2=warnings, 3=info, 4=full (default ${CONFIG_level_logging})"
      fi
      if [[ $LIB_options == *s* ]]
      then
        help+="
  -s simulate: perform dry run without real permanent actions (writing, deleting, ...)"
      fi
      if [[ $LIB_options == *f* ]]
      then
        help+="
  -f config_file: configuration file to be used"
      fi
      if [[ $LIB_options == *t* ]]
      then
        help+="
  -t status_file
     tick: file for writing working status"
      fi
      ;;
    f)
      help="
The script is configurable by altering values of 'CONFIG_...' parameters
in itself or by putting them into the configuration file.
"
      ;;
    esac
  done
  shift $(($OPTIND-1))
  echo "$help"
}

# @info:  Display run message of the script
# @args:  START | STOP | BREAK
# @return:  none
# @deps:  none
show_manifest () {
  local action
  case "$1" in
  START)
    action="Starting"
    ;;
  STOP)
    action="Stopping"
    ;;
  BREAK)
    action="Breaking"
    ;;
  *)
    action="Running"
    ;;
  esac
  echo_text -ba -${CONST_level_verbose_mail} "${action} ${CONFIG_script} ${CONFIG_version} for system $(hostname) -- $(date)."
  log_text -$CONST_level_logging_info "${action}."
}

# @info:  Actions necessary at premature finishing script invoked by 'trap'
# @args:  none
# @return:  none
# @deps:  none
break_script () {
  show_manifest BREAK
}

# @info:  Actions at finishing script invoked by 'trap'
# @args:  none
# @return:  none
# @deps:  none
stop_script () {
  show_manifest STOP
}

# @info:  Actions at initializing script
# @args:  none
# @return:  none
# @deps:  none
init_script () {
  trap break_script EXIT
  show_manifest START
  check_level_verbose
  check_level_loging
  check_commands
  process_config
  process_credentials
  check_root
}

# @info:  Send data to ThingsBoard IoT platform
# @args:
#   $1 ... HTTP request payload as JSON object
# @return: none
# @deps:  global CONFIG_inet variables
write2thingsboard () {
  local payload msg resp opt
  payload="$1"
  msg="HTTP request to ThingsBoard"
  opt=""
  echo_text -hp -${CONST_level_verbose_info} "${msg}$(dryrun_token)${sep}${payload}${sep}"
	if [[ ${CONFIG_flag_dryrun} -eq 0 && -n "${payload}" ]]
	then
		# Compose and send HTTP request
		for (( i=0; i<${CONFIG_thingsboard_fail_count}; i++ ))
		do
			resp=$(curl --location --silent \
--write-out %{http_code} \
--output /dev/null \
--connect-timeout 3 \
--request POST "${CONFIG_thingsboard_host}/api/v1/${CONFIG_thingsboard_token}/telemetry" \
--header "Content-Type: application/json" \
--data-raw "${payload}")
			if [[ ${resp} -eq ${CONFIG_thingsboard_code_OK} || ${resp} -eq 0 ]]
			then
				break
			fi
			sleep ${CONFIG_thingsboard_fail_delay}
		done
	else
		resp=${CONFIG_thingsboard_code_OK}
	fi
	result="HTTP status code ${resp}"
	if [[ ${resp} -ne ${CONFIG_thingsboard_code_OK} ]]
	then
		echo_text -${CONST_level_verbose_info} "failed with ${result}. Exiting."
		if [[ ${resp} -eq 0 ]]
		then
			opt="-s"
		fi
    status_text -aF "${msg}${sep}${result}"
		fatal_error ${opt} "${msg} failed with ${result}."
	else
		echo_text -${CONST_level_verbose_info} "${resp}."
		log_text -IS "${msg}${sep}${result}"
    status_text -a "${msg}${sep}${result}"
	fi
}
# <- END _functions
