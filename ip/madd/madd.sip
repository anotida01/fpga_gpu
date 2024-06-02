set_global_assignment -entity "madd" -library "lib_madd" -name IP_TOOL_NAME "altera_mult_add"
set_global_assignment -entity "madd" -library "lib_madd" -name IP_TOOL_VERSION "20.1"
set_global_assignment -entity "madd" -library "lib_madd" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_madd" -name SPD_FILE [file join $::quartus(sip_path) "madd.spd"]

set_global_assignment -library "lib_madd" -name MISC_FILE [file join $::quartus(sip_path) "madd_sim/madd.v"]
