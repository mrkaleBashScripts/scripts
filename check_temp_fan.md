# Check internal SoC temperature, control fan, and publish to MQTT topics
The script is supposed to be used under cron.

- For debuging purposes it is supposed to be run in simulation mode with various input arguments emulating exceeding particular limited temperatures or controlling a fan.
- The script logs temperatures and other messages into the syslog, if it is installed on the system.
- The script publishes curren temperature in millicentigrades and fan control GPIO pin value to the MQTT topics.

## Name
**check_temp_fan.sh** - Check the SoC temperature and control fan

## Synopsis
    check_temp_fan.sh [OPTION [ARG]]

## Description
Script checks the internal temperature of the CPU, turns on or off connected fan, publishes to MQTT topics, and warns or shuts down the system if temperature limits are exceeded.

- Script has to be run under root privileges (sudo ...).
- Script is supposed to run under cron.
- Script logs to `user.log`.
- Script may write its working status into a status (tick) file if defined, what may be considered as a monitoring heartbeat of the script especially then in normal conditions it produces no output.
- Status file should be located in the temporary file system (e.g., in the folder `/tmp`) or other folder located in the RAM in order to reduce writes to the SD card. 
- Script ouputs all error messages into standard error output.
- All essential parameters are defined in the section of configuration parameters. Their description is provided locally. Script can be configured by changing values of them.
- Configuration parameters in the script can be overriden by the corresponding ones in a configuration file declared in the command line.
- In simulation mode the script ommits shutting down the system and changing values of the fan control GPIO pin.
- The halting (shutdown) temperature limit is the configurable percentage of maximal temperature written in `/sys/class/thermal/thermal_zone0/trip_point_0_temp`. 
- The warning temperature limit is the configurable percentage of the maximal temperature.
- The current temperature is read from `/sys/class/thermal/thermal_zone0/temp`.
- At verbose and log level `info` the script outputs and logs the current temperature.
- Script outputs (emails in the cron) warning message only than the currently warned temperature is greater than previously warned one or if the temperature meantime sinks under the warning temperature. It suppresses annoying repeatable warning emails during a continuous warning temperature time period.
- Script outputs (emails in the cron) turning on or off a fan.
- Script publishes temperatures and controlling a fan to corresponding MQTT topics.  

## Options and arguments
    -h                 help: show this help and exit
    -s                 simulate: perform dry run without shutting down and manipulating GPIO pin
    -V                 Version: show version information and exit
    -c                 configs: print listing of all configuration parameters
    -l log_level       logging: level of logging intensity to syslog
                       0=none, 1=errors (default), 2=warnings, 3=info, 4=full
    -o verbose_level   output: level of verbosity
                       0=none, 1=errors (default), 2=mails, 3=info, 4=functions, 5=full
    -m                 mailing: display all processing messages; alias for '-o2'
    -v                 verbose: display all processing messages; alias for '-o5'
    -f config_file     file: configuration file to be used
    -t status_file     tick: status file to be used
    -S                 Sensors: List all sensor and fan parameters.
    -P GpioFan         Fan control GPIO pin: Numbering for WiringPi, WiringOP library.
    -1                 Force warning: Simulate reaching warning temperature.
    -2                 Force error: Simulate reading exactly maximal temperature.
    -3                 Force fatal: Simulate exceeding shutdown temperature.
    -4                 Force fan on. Simulate exceeding fan turning on temperature.
    -5                 Force fan off. Simulate exceeding fan turning off temperature.

## Dependency
The script uses the script `scripts_lib.sh`, which is supposed to be loaded to current script as a library. It can be considered as a framework for it. It contains common configuration parameters and common functions definitions.

## Configuration
The configuration is predefined by the values of configuration parameters in the script's section **\_config**. Each of configuration parameters begins with the prefix **CONFIG\_**. Here are some of the most interesting ones. Change them reasonably and if you know, what you are doing. The configuration parameters can be overriden by corresponding ones, if they are present in the configuration file declared by an argument of the option "**-f**". Finally some of them may be overriden by respective command line options. So the precedence priority of configuration parameters is as follows where the latest is valid:

1. Script
2. Command line option
3. Configuration file

#### CONFIG\_gpio\_fan
This parameter defines the fan control GPIO pin, which is used to control a fan. The numbering used should be for library *WiringPi* or *WiringOP*. Default value is **15**.

#### CONFIG\_fanoff\_perc
This parameter defines the fan turning off temperature limit as a percentage rate of the maximal temperature limit. Default value is **75%**. If the temperature sinks at this limit or less, a fan is turned off by setting the fan control GPIO pin value to *LOW*. The script outputs this action to the standard output, which is usually emailed by the cron, as well as to the system log and tick (status) file.

#### CONFIG\_fanon\_perc
This parameter defines the fan turning on temperature limit as a percentage rate of the maximal temperature limit. Default value is **85%**. If the temperature exceeds this limit, a fan is turned on by setting the fan control GPIO pin value to *HIGH*. The script outputs this action to the standard output, which is usually emailed by the cron, as well as to the system log and tick (status) file.

#### CONFIG\_warning\_perc
This parameter defines the warning temperature limit as a percentage rate of the maximal temperature limit. Default value is **90%**. If the temperature exceeds this warning limit, the script outputs alert to the standard output, which is usually emailed by the cron, as well as to the system log and tick (status) file.

#### CONFIG\_shutdown\_perc
This parameter defines the halting temperature limit as a percentage rate of the maximal temperature limit. Default value is **95%**. If the temperature exceeds this halting limit, the script outputs alert to the standard output, which is usually emailed by the cron, as well as to the system log and tick (status) file, and finally shuts down the system in order to prevent the overheating destruction.

#### CONFIG\_mqtt\_topic\_temp
This parameter defines the MQTT topic name, to which the script publishes the current SoC temperature in milicentigrades (e.g., 42369 for 42.369&deg;C ) at its start. Default value is

	<hostname>/server/temp

where *<hostname>* is placeholder for the hostname of the system. 

#### CONFIG\_mqtt\_topic\_fan
This parameter defines the MQTT topic name, to which the script publishes the current state of a fan in form of logical value (0 or 1) of fan control GPIO pin at its start and at potential change of its value at fan temperature limits. Default value is

	<hostname>/server/fan

where *<hostname>* is placeholder for the hostname of the system. 

#### CONFIG\_level\_logging
This parameter defines the level or intensity of logging to system log **user.log**. It takes an integer parameter from the following list

- `0` ... no logging to system log
- `1` ... logging just error messages
- `2` ... logging warning messages as well as all messages from previous logging levels
- `3` ... logging information messages as well as all messages from previous logging levels
- `4` ... logging all possible messages that can be logged

#### CONFIG\_level\_verbose
This parameter defines the level of verbosity to the console. It takes an integer parameter from the following list

- `0` ... no messages
- `1` ... just error messages
- `2` ... messages for emailing as well as all messages from previous verbose levels
- `3` ... information messages as well as all messages from previous verbose levels
- `4` ... messages from essetial functions as well as all messages from previous verbose levels
- `5` ... all possible messages

#### CONFIG\_config
The path to a configuration file, which can substitute command line options and parameters. It is read in the script as a shell script so you can abuse that fact if you so want to. It should contain just configuration variables assignment that you want to overide in the form 

    CONFIG_param=value

The configuration file should not contain any programmatic code in order not to change the behaviour of the script.

## License
This script is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.
