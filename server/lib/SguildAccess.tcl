# $Id: SguildAccess.tcl,v 1.5 2008/01/30 04:07:13 bamm Exp $ #

# Load up the access lists.
proc LoadAccessFile { filename } {
  global CLIENT_ACCESS_LIST SENSOR_ACCESS_LIST
  LogMessage "Loading access list: $filename" 
  set CANYFLAG 0
  set SANYFLAG 0
  for_file line $filename {
    # Ignore comments (#) and blank lines.
    if { ![regexp ^# $line] && ![regexp {^\s*$} $line] } {
      if { [regexp {^\s*client} $line] && $CANYFLAG != "1" } {
        set ipaddr [lindex $line 1]
        if { $ipaddr == "ANY" || $ipaddr == "any" } {
          set CANYFLAG 1
          set CLIENT_ACCESS_LIST ANY
          LogMessage "Client access list set to ALLOW ANY." 
        } else {
          LogMessage "Adding client to access list: $ipaddr"
          lappend CLIENT_ACCESS_LIST $ipaddr
        }
      } elseif { [regexp {^\s*sensor} $line] && $SANYFLAG != "1" } {
        set ipaddr [lindex $line 1]
        if { $ipaddr == "ANY" || $ipaddr == "any" } {
          set SANYFLAG 1
          set SENSOR_ACCESS_LIST ANY
          LogMessage "Sensor access list set to ALLOW ANY." 
        } else {
          LogMessage "Adding sensor to access list: $ipaddr"
          lappend SENSOR_ACCESS_LIST $ipaddr
        }
      } else {
        ErrorMessage "ERROR: Parsing $filename: Format error: $line"
      }
    }
  }
  if {![info exists CLIENT_ACCESS_LIST] || $CLIENT_ACCESS_LIST == "" } {
    ErrorMessage "ERROR: No client access lists found in $filename."
  }
  if {![info exists SENSOR_ACCESS_LIST] || $SENSOR_ACCESS_LIST == "" } {
    ErrorMessage "ERROR: No sensor access lists found in $filename."
  }
                                                                                                                                                       
}

proc ValidateSensorAccess { ipaddr } {
  global SENSOR_ACCESS_LIST
  LogMessage "Validating sensor access: $ipaddr : "
  set RFLAG 0
  if { $SENSOR_ACCESS_LIST == "ANY" } {
    set RFLAG 1
  } elseif { [info exists SENSOR_ACCESS_LIST] && [lsearch -exact $SENSOR_ACCESS_LIST $ipaddr] >= 0 } {
    set RFLAG 1
  }
  return $RFLAG
}
proc ValidateClientAccess { ipaddr } {
  global CLIENT_ACCESS_LIST
  LogMessage "Validating client access: $ipaddr"
  set RFLAG 0
  if { $CLIENT_ACCESS_LIST == "ANY" } {
    set RFLAG 1
  } elseif { [info exists CLIENT_ACCESS_LIST] && [lsearch -exact $CLIENT_ACCESS_LIST $ipaddr] >= 0 } {
    set RFLAG 1
  }
  return $RFLAG
}


proc CreateUsersFile { fileName } {
  set dirName [file dirname $fileName]
  if { ![file exists $dirName] || ![file isdirectory $dirName] } {
    if [catch {file mkdir $dirName} dirError] {
      ErrorMessage "Error: Could not create $dirName: $dirError"
    }
  }
  if [catch {open $fileName w} fileID] {
    ErrorMessage "Error: Could not create $fileName: $fileID"
  } else {
    puts $fileID "#"
    puts $fileID "# WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING"
    puts $fileID "#"
    puts $fileID "# This file is automatically generated. Please do not edit it by hand."
    puts $fileID "# Doing so could corrupt the file and make it unreadable."
    puts $fileID "#"
    puts $fileID "# WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING"
    puts $fileID "#"
    close $fileID
  }
}

proc DelUser { userName USERS_FILE } {
  set fileID [open $USERS_FILE r]
  set USERFOUND 0
  for_file line $USERS_FILE {
    if { ![regexp ^# $line] && ![regexp ^$ $line] } {
      # User file is boobie deliminated
      set tmpLine $line
      if { $userName == [ctoken tmpLine "(.)(.)"] } {
        set USERFOUND 1
      } else {
        lappend tmpData $line
      }
    } else {
      lappend tmpData $line
    }
  }
  close $fileID
  if { !$USERFOUND } {
    puts "ERROR: User \'$userName\' does NOT exist in $USERS_FILE"
  } else {
    if [catch {open $USERS_FILE w} fileID] {
      puts "ERROR: Could not edit $USERS_FILE: $fileID"
    } else {
      foreach line $tmpData {
        puts $fileID $line
      }
      close $fileID
    }
  }
}

proc AddUser { userName USERS_FILE } {
  # Usernames must be alpha-numeric
  if { ![string is alnum $userName] } {
    puts "ERROR: Username must be alpha-numeric"
    return
  }

  # Usernames cannot be longer the 16 chars
  if { [string length $userName] > 16 } {
    puts "ERROR: Username cannot be longer than 16 characters."
    return
  }

  # Make sure we aren't adding a dupe.
  set fileID [open $USERS_FILE r]
  for_file line $USERS_FILE {
    if { ![regexp ^# $line] && ![regexp ^$ $line] } {
      # User file is boobie deliminated
      if { $userName == [ctoken line "(.)(.)"] } {
	puts "ERROR: User \'$userName\' already exists in $USERS_FILE."
        return
      }
    }
  }
  close $fileID
  # Get a passwd
  puts -nonewline "Please enter a passwd for $userName: "
  flush stdout
  exec stty -echo
  set passwd1 [gets stdin]
  exec stty echo
  puts -nonewline "\nRetype passwd: "
  flush stdout
  exec stty -echo
  set passwd2 [gets stdin]
  exec stty echo
  puts ""
  if { $passwd1 != $passwd2} {
    puts "ERROR: Passwords didn't match."
    puts "$USERS_FILE NOT updated."
    return
  }
  set salt [format "%c%c" [GetRandAlphaNumInt] [GetRandAlphaNumInt] ]
  # make a hashed passwd
  set hashPasswd [::sha1::sha1 "${passwd1}${salt}"]
  set fileID [open $USERS_FILE a]
  puts $fileID "${userName}(.)(.)${salt}${hashPasswd}"
  close $fileID
  puts "User \'$userName\' added successfully"
}
proc ValidateUser { socketID username } {
  global USERS_FILE validSockets socketInfo userIDArray
  fileevent $socketID readable {}
  fconfigure $socketID -buffering line
  if { ![file exists $USERS_FILE] } {
    ErrorMessage "Fatal Error! Cannot access $USERS_FILE."
  }
  set VALID 0
  set nonce [format "%c%c%c" [GetRandAlphaNumInt] [GetRandAlphaNumInt] [GetRandAlphaNumInt] ]
  for_file line $USERS_FILE {
    if { ![regexp ^# $line] && ![regexp ^$ $line] } {
      # Probably should check for corrupted info here
      set tmpUserName [ctoken line "(.)(.)"]
      set tmpSaltHash [ctoken line "(.)(.)"]
      if { $tmpUserName == $username } {
        set VALID 1
        set tmpSalt [string range $tmpSaltHash 0 1]
        set finalCheck [::sha1::sha1 "${nonce}${tmpSaltHash}"]
        break
      }
    }
  }
  if {$VALID} {
    puts $socketID "$tmpSalt $nonce"
    set finalClient [gets $socketID]
    if { $finalClient == $finalCheck } {
      set userIDArray($socketID) [GetUserID $username]
      DBCommand\
       "UPDATE user_info SET last_login='[GetCurrentTimeStamp]' WHERE uid=$userIDArray($socketID)"
      lappend validSockets $socketID
      catch { SendSocket $socketID "UserID $userIDArray($socketID)" } tmpError
      SendSystemInfoMsg sguild "User $username logged in from [lindex $socketInfo($socketID) 0]"
      lappend socketInfo($socketID) $username
    } else {
      set validSockets [ldelete $validSockets $socketID]
      catch {SendSocket $socketID "UserID INVALID"} tmpError
      SendSystemInfoMsg sguild "User $username denied access from [lindex $socketInfo($socketID) 0]"
    }
  } else {
    #Not a valid user. Make up info.
    set tmpSalt [format "%c%c" [GetRandAlphaNumInt] [GetRandAlphaNumInt] ]
    set finalCheck [::sha1::sha1 "${nonce}${tmpSalt}"]
    puts $socketID "$tmpSalt $nonce"
    set finalClient [gets $socketID]
    set validSockets [ldelete $validSockets $socketID]
    catch {SendSocket $socketID "UserID INVALID"} tmpError
    SendSystemInfoMsg sguild "User $username denied access from [lindex $socketInfo($socketID) 0]"
  }
  fileevent $socketID readable [list ClientCmdRcvd $socketID]
}






