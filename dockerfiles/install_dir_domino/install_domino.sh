#!/bin/bash
############################################################################
# Copyright Nash!Com, Daniel Nashed 2019, 2023 - APACHE 2.0 see LICENSE
# Copyright IBM Corporation 2015, 2019 - APACHE 2.0 see LICENSE
############################################################################

INSTALL_DIR=$(dirname $0)
export LANG=C

# Include helper functions & defines
. $INSTALL_DIR/script_lib.sh

# Installer string definitions to check for successful installation
DOM_V12_STRING_OK="Domino Server Installation Successful"
FP_STRING_OK="The installation completed successfully."
HF_STRING_OK="The installation completed successfully."
LP_STRING_OK="Selected Language Packs are successfully installed."
TRAVELER_STRING_OK="Installation completed successfully."
TRAVELER_STRING_WARNINGS="Installation completed with warnings."
RESTAPI_STRING_OK="Installation: success"

HF_UNINSTALL_STRING_OK="The installation completed successfully."
JVM_STRING_OK="Patch was successfully applied."
JVM_STRING_FP_OK="Tree diff file patch successful!"

# Log Files
INST_DOM_LOG=$DOMDOCK_LOG_DIR/install_domino.log
INST_FP_LOG=$DOMDOCK_LOG_DIR/install_fp.log
INST_HF_LOG=$DOMDOCK_LOG_DIR/install_hf.log
INST_LP_LOG=$DOMDOCK_LOG_DIR/install_domlp.log
INST_TRAVELER_LOG=$DOMDOCK_LOG_DIR/install_traveler.log
INST_RESTAPI_LOG=$DOMDOCK_LOG_DIR/install_restapi.log


install_domino()
{

  #On Ubuntu & Debian Domino 14 requires to disable requirements checks
  if [ -x /usr/bin/apt-get ]; then
    log_space "Info: Disable Domino requirements check for Linux distribution."
    export INSTALL_NO_CHECK=1
  fi

  INST_VER=$PROD_VER

  check_installed_version ver $INST_VER
  if [ "$?" = "1" ]; then
    INST_VER=""
  fi

  if [ -z "$PROD_FP" ]; then
    INST_FP=""
  else
    INST_FP=$PROD_VER$PROD_FP

    check_installed_version fp $INST_FP
    if [ "$?" = "1" ]; then
      INST_FP=""
    fi
  fi

  if [ -z "$PROD_HF" ]; then
    INST_HF=""
  else
    INST_HF=$PROD_VER$PROD_FP$PROD_HF

    check_installed_version hf $INST_HF
    if [ "$?" = "1" ]; then
      INST_HF=""
    fi
  fi

  header "Downloading Domino Installation files ..."

  if [ -n "$INST_VER" ]; then

    # If explicitly specified just download and skip calculating hash
    if [ -n "$PROD_DOWNLOAD_FILE" ]; then
      echo "Info: Not checking download hash for [$PROD_DOWNLOAD_FILE]"
      DOWNLOAD_NAME="$PROD_DOWNLOAD_FILE"
      download_and_check_hash "$DownloadFrom" "$DOWNLOAD_NAME" domino_server . nohash
    else
      get_download_name $PROD_NAME $INST_VER
      download_and_check_hash "$DownloadFrom" "$DOWNLOAD_NAME" domino_server
    fi
  fi

  if [ -n "$INST_FP" ]; then

    # If explicitly specified just download and skip calculating hash
    if [ -n "$PROD_FP_DOWNLOAD_FILE" ]; then
      echo "Info: Not checking download hash for [$PROD_FP_DOWNLOAD_FILE]"
      DOWNLOAD_NAME="$PROD_FP_DOWNLOAD_FILE"
      download_and_check_hash "$DownloadFrom" "$DOWNLOAD_NAME" domino_fp . nohash
    else
      get_download_name $PROD_NAME $INST_FP domino_fp
      download_and_check_hash "$DownloadFrom" "$DOWNLOAD_NAME" domino_fp
    fi
  fi

  if [ -n "$INST_HF" ]; then

    # If explicitly specified just download and skip calculating hash
    if [ -n "$PROD_HF_DOWNLOAD_FILE" ]; then
      echo "Info: Not checking download hash for [$PROD_HF_DOWNLOAD_FILE]"
      DOWNLOAD_NAME="$PROD_HF_DOWNLOAD_FILE"
      download_and_check_hash "$DownloadFrom" "$DOWNLOAD_NAME" domino_hf . nohash
    else
      get_download_name $PROD_NAME $INST_HF domino_hf
      download_and_check_hash "$DownloadFrom" "$DOWNLOAD_NAME" domino_hf
    fi
  fi

  if [ -n "$DOMLP_VER" ]; then
    get_download_name domlp $DOMLP_VER
    download_and_check_hash "$DownloadFrom" "$DOWNLOAD_NAME" domino_lp . LNXDomLP
  fi

  # On Ubuntu and Debian the default shell for /bin/sh is /bin/dash
  # Change the shell during installation to /bin/bash and remember the change
  set_sh_shell bash

  if [ -n "$INST_VER" ]; then
    header "Installing $PROD_NAME $INST_VER"
    log_space "Running Domino Silent Install -- This takes a while ..."

    # If no response file is specified, use the V14 install all response file
    if [ -z "$DominoResponseFile" ]; then
      # Install Domino V14 including Nomad Server and OnTime
      case "$PROD_VER" in
        V14*|14*)
          DominoResponseFile=domino14_full_install.properties
          ;;

        *)
          DominoResponseFile=domino_install.properties
          ;;
      esac
    fi

    CURRENT_DIR=$(pwd)
    cd domino_server/linux64
    ./install -f "$INSTALL_DIR/$DominoResponseFile" -i silent
    cd $CURRENT_DIR

    INSTALL_LOG=$(find $LOTUS -name "HCL_Domino_Install_*.log")

    mv "$INSTALL_LOG" "$INST_DOM_LOG"
    check_file_str "$INST_DOM_LOG" "$DOM_V12_STRING_OK"

    if [ "$?" = "1" ]; then
      echo
      log_ok "Domino installed successfully"

      # Store Domino Version Information
      set_domino_version ver

    else
      dump_file "$INST_DOM_LOG"
      log_error "Domino Installation failed!!!"
      exit 1
    fi

    remove_directory domino_server

    # Copy HCL container license file
    if [ "$CONTAINER_INSTALLER" = "hcl" ]; then
      cp $INSTALL_DIR/Notices.txt $Notes_ExecDirectory/license
    fi

    # Copy license files
    mkdir -p /licenses
    cp $Notes_ExecDirectory/license/*.txt /licenses

  fi

  if [ -n "$DOMLP_VER" ]; then
    LP_LANG=$(echo "$DOMLP_VER" | cut -d'-' -f1)
    header "Installing Language Pack $DOMLP_VER ($LP_LANG)"
    log_space "Running Domino Language Pack Silent Install -- This takes a while ..."

    CURRENT_DIR=$(pwd)

    cd domino_lp
    chmod +x LNXDomLP

    #./LNXDomLP -f $INSTALL_DIR/domlp_${DOMLP_VER}.properties -i silent -DSILENT_INI_PATH=${INSTALL_DIR}/domlp_${DOMLP_VER}_silent.ini

    # Generate LPSilent install ini file
    local DOMINO_LP_INI="$(pwd)/domlp.ini"
    local DOMLP_LANG_LCASE=$(echo "$DOMLP_VER" | cut -d"-" -f1 | awk '{print tolower($0)}')

    echo "[Notes]" > "$DOMINO_LP_INI"
    echo "INSTALL_TYPE=REPLACE" >> "$DOMINO_LP_INI"
    echo "DOMINO_ARCH=64" >> "$DOMINO_LP_INI"
    echo "TOTAL_DATAPATHS=1" >> "$DOMINO_LP_INI"
    echo "TOTAL_LANGUAGES=1" >> "$DOMINO_LP_INI"
    echo "DOMINO_INSTALL=NO" >> "$DOMINO_LP_INI"
    echo "CORE_PATH=$DOMINO_DATA_PATH" >> "$DOMINO_LP_INI"
    echo "CORE_DISPLAY_PATH=$LOTUS" >> "$DOMINO_LP_INI"
    echo "DATA_PATH_00=/local/notesdata" >> "$DOMINO_LP_INI"
    echo "LANGUAGES_00=$DOMLP_LANG_LCASE" >> "$DOMINO_LP_INI"

    # Invoke LP Installer
    ./LNXDomLP -i silent "-DSILENT_INI_PATH=$DOMINO_LP_INI"

    if [ ! -e /opt/hcl/domino/LPLog.txt ]; then

      echo Cannot find LPLog.txt in /opt/hcl/domino
      print_delim
      ls -l /opt/hcl/domino
      print_delim

      log_error "Language Pack Installation failed!!!"
      exit 1
    fi

    # Move LP install log

    mv /opt/hcl/domino/LPLog.txt "$INST_LP_LOG"
    check_file_str "$INST_LP_LOG" "$LP_STRING_OK"

    if [ "$?" = "1" ]; then
      echo
      log_ok "Language Pack installed successfully"

    else
      dump_file "$DOMINO_LP_INI"
      dump_file "$INST_LP_LOG"
      log_error "Language Pack Installation failed!!!"
      exit 1
    fi

    cd $CURRENT_DIR
    remove_directory domino_lp
    remove_directory /tmp/lpFolder
  fi

  if [ -n "$INST_FP" ]; then
    header "Installing Fixpack $INST_FP"

    log_space "Running Domino Fixpack Silent Install -- This takes a while ..."

    CURRENT_DIR=$(pwd)
    cd domino_fp/linux64/domino

    ./install -script script.dat > $INST_FP_LOG
    cd $CURRENT_DIR

    check_file_str "$INST_FP_LOG" "$FP_STRING_OK"

    if [ "$?" = "1" ]; then
    	echo
      log_ok "Fixpack installed successfully"

      # Store Domino Fixpack Information
      set_domino_version fp

    else

      dump_file $INST_FP_LOG
      log_error "Fixpack Installation failed!!!"
      exit 1
    fi

    remove_directory domino_fp

  fi

  if [ -n "$INST_HF" ]; then
    header "Installing IF/HF INST_HF"

    log_space "Running Domino Iterimsfix/Hotfix Silent Install -- This takes a while ..."

    CURRENT_DIR=$(pwd)
    cd domino_hf/linux64

    ./install -script script.dat > $INST_HF_LOG
    cd $CURRENT_DIR

    check_file_str "$INST_HF_LOG" "$HF_STRING_OK"

    if [ "$?" = "1" ]; then
      echo
      log_ok "InterimsFix/HotFix installed successfully"

      # Store Domino Interimsfix/Hotfix Information
      set_domino_version hf

    else

      dump_file hf.log
      log_error "InterimsFix/HotFix Installation failed!!!"

      exit 1
    fi

    remove_directory domino_hf

  fi

  # Switch back sh shell if changed /bin/sh for Ubuntu/Debian from /bin/dash to /bin/bash
  if [ -n "$ORIG_SHELL_LINK" ]; then
    set_sh_shell "$ORIG_SHELL_LINK"
  fi

  return 0
}

install_osgi_file()
{
  local SOURCE=$1
  local TARGET="$PLUGINS_FOLDER/$(basename $1)"

  install_file "$SOURCE" "$TARGET" root root 755
}

install_verse()
{
  local ADDON_NAME=verse
  local ADDON_VER=$1

  if [ -z "$ADDON_VER" ]; then
    return 0
  fi

  header "$ADDON_NAME Installation"

  get_download_name $ADDON_NAME $ADDON_VER
  download_and_check_hash "$DownloadFrom" "$DOWNLOAD_NAME" "$ADDON_NAME"

  header "Installing $ADDON_NAME $ADDON_VER"

  OSGI_FOLDER="$Notes_ExecDirectory/osgi"
  PLUGINS_FOLDER=$OSGI_FOLDER"/shared/eclipse/plugins"

  mkdir -p $PLUGINS_FOLDER
  CURRENT_DIR=$(pwd)
  cd $ADDON_NAME
  echo "Unzipping files .."
  unzip -q  *.zip
  unzip -q HCL_Verse.zip

  echo "Copying files .."

  for JAR in eclipse/plugins/*.jar; do
    install_osgi_file "$JAR"
  done

  for JAR in *.jar; do
    install_osgi_file "$JAR"
  done

  install_file "iwaredir.ntf" "$DOMINO_DATA_PATH/iwaredir.ntf" $DOMINO_USER $DOMINO_GROUP 644

  log_space Installed $ADDON_NAME

  cd $CURRENT_DIR
}

install_nomad()
{
  local ADDON_NAME=nomad
  local ADDON_VER=$1

  if [ -z "$ADDON_VER" ]; then
    return 0
  fi

  header "$ADDON_NAME Installation"

  get_download_name $ADDON_NAME $ADDON_VER

  header "Installing $ADDON_NAME $ADDON_VER"

  download_and_check_hash "$DownloadFrom" "$DOWNLOAD_NAME" "$Notes_ExecDirectory"

  log_space Installed $ADDON_NAME
}


install_leap()
{
  local ADDON_NAME=leap
  local ADDON_VER=$1

  if [ -z "$ADDON_VER" ]; then
    return 0
  fi

  header "$ADDON_NAME Installation"

  get_download_name $ADDON_NAME $ADDON_VER

  header "Installing $ADDON_NAME $ADDON_VER"

  local OSGI_FOLDER="$Notes_ExecDirectory/osgi"
  local OSGI_VOLT_FOLDER=$OSGI_FOLDER"/volt"
  local PLUGINS_FOLDER=$OSGI_VOLT_FOLDER"/eclipse/plugins"
  local VOLT_DATA_DIR=$DOMINO_DATA_PATH"/volt"
  local LINKS_FOLDER=$OSGI_FOLDER"/rcp/eclipse/links"
  local LINK_PATH=$OSGI_FOLDER"/volt"
  local LINK_FILE=$LINKS_FOLDER"/volt.link"

  create_directory "$VOLT_DATA_DIR" $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  create_directory "$OSGI_VOLT_FOLDER" root root 755
  create_directory "$LINKS_FOLDER" root root 755
  create_directory "$PLUGINS_FOLDER" root root 755

  echo 'path='$LINK_PATH > $LINK_FILE

  download_and_check_hash "$DownloadFrom" "$DOWNLOAD_NAME" "$ADDON_NAME"

  cd "$ADDON_NAME"

  echo "Unzipping files .."
  unzip -q *.zip

  echo "Copying files .."
  cp -f "templates/"* "$VOLT_DATA_DIR"
  cp -f "bundles/"* "$PLUGINS_FOLDER"

  cd ..
  remove_directory $ADDON_NAME

  header "Final Steps & Configuration"

  # Ensure permissons are set correctly for data directory
  chown -R $DOMINO_USER:$DOMINO_GROUP $DOMINO_DATA_PATH

  # Copy demopack.zip if present in install dir
  if [ -e "$INSTALL_DIR/demopack.zip" ]; then
    cp "$INSTALL_DIR/demopack.zip" "$DOMDOCK_DIR/demopack.zip"
  fi

  # Set add-on version
  echo $ADDON_VER > "$DOMDOCK_TXT_DIR/${ADDON_NAME}_ver.txt"
  echo $ADDON_VER > "$DOMINO_DATA_PATH/${ADDON_NAME}_ver.txt"

  # Copy add-on data for Domino Leap, even it will be in the full data dir

  local CURRENT_DIR=$(pwd)
  cd $DOMINO_DATA_PATH

  local INSTALL_ADDON_DATA_TAR=$DOMDOCK_DIR/install_data_addon_${ADDON_NAME}.taz
  tar -czf "$INSTALL_ADDON_DATA_TAR" volt ${ADDON_NAME}_ver.txt

  cd "$CURRENT_DIR"

  log_space Installed $ADDON_NAME
}


install_traveler()
{
  local ADDON_NAME=traveler
  local ADDON_VER=$1

  if [ -z "$ADDON_VER" ]; then
    return 0
  fi

  header "$ADDON_NAME Installation"

  get_download_name $ADDON_NAME $ADDON_VER

  header "Installing $ADDON_NAME $ADDON_VER"

  download_and_check_hash "$DownloadFrom" "$DOWNLOAD_NAME" "$ADDON_NAME" 

  if [ -n "$(find /opt/hcl/domino/notes/ -maxdepth 1 -name "120002*")" ]; then
    TRAVELER_INSTALLER_PROPERTIES=$INSTALL_DIR/installer_traveler_domino1202.properties
  elif [ -n "$(find /opt/hcl/domino/notes/ -maxdepth 1 -name "120001*")" ]; then
    TRAVELER_INSTALLER_PROPERTIES=$INSTALL_DIR/installer_traveler_domino1201.properties
  elif [ -n "$(find /opt/hcl/domino/notes/ -maxdepth 1 -name "120000*")" ]; then
    TRAVELER_INSTALLER_PROPERTIES=$INSTALL_DIR/installer_traveler_domino12.properties
  else
    # Assume latest version (No version check and no version specified)
    TRAVELER_INSTALLER_PROPERTIES=$INSTALL_DIR/installer_traveler_hcl.properties
  fi

  cd "$ADDON_NAME"

  header "Running Traveler silent install"

  ./TravelerSetup -f $TRAVELER_INSTALLER_PROPERTIES -i SILENT -l en > $INST_TRAVELER_LOG 2>&1

  # Save installer logs into image for reference if present
  copy_log "$DOMINO_DATA_PATH/IBM_TECHNICAL_SUPPORT/traveler/logs/TravelerInstall.log" "$DOMDOCK_LOG_DIR"

  check_file_str "$INST_TRAVELER_LOG" "$TRAVELER_STRING_OK"

  if [ "$?" = "1" ]; then
    echo
    log_ok "$PROD_NAME $INST_VER installed successfully"

  else

    check_file_str "$INST_TRAVELER_LOG" "$TRAVELER_STRING_WARNINGS"

    if [ "$?" = "1" ]; then
      echo
      log_ok "$PROD_NAME $INST_VER installed successfully (with warnings)"
    else

      dump_file "$INST_TRAVELER_LOG"
      dump_file "/tmp/install/traveler/InstallerError.log"
      log_error "Traveler Installation failed!!!"
      exit 1
    fi
  fi

  # Save notes.ini for Traveler add-on ini
  cp -f $DOMINO_DATA_PATH/notes.ini $DOMDOCK_DIR/traveler_install_notes.ini

  # Set add-on version
  echo $ADDON_VER > "$DOMDOCK_TXT_DIR/${ADDON_NAME}_ver.txt"
  echo $ADDON_VER > "$DOMINO_DATA_PATH/${ADDON_NAME}_ver.txt"

  # Copy add-on data for Traveler, even it will be in the full data dir
  local INSTALL_ADDON_DATA_TAR=$DOMDOCK_DIR/install_data_addon_${ADDON_NAME}.taz

  local CURRENT_DIR=$(pwd)
  cd $DOMINO_DATA_PATH
  tar -czf "$INSTALL_ADDON_DATA_TAR" traveler domino/workspace domino/html/travelerclients ${ADDON_NAME}_ver.txt

  cd "$CURRENT_DIR"

  log_space Installed $ADDON_NAME
}


install_capi()
{
  local ADDON_NAME=capi
  local ADDON_VER=$1

  if [ -z "$ADDON_VER" ]; then
    return 0
  fi

  header "$ADDON_NAME Installation"

  get_download_name $ADDON_NAME $ADDON_VER
  download_and_check_hash "$DownloadFrom" "$DOWNLOAD_NAME" "$ADDON_NAME"

  header "Installing $ADDON_NAME $ADDON_VER"

  CURRENT_DIR=$(pwd)

  cd $ADDON_NAME
  echo "Unzipping files .."

  # Domino 14 C-API ZIP has different structure
  if [ "$ADDON_VER" = "14.0" ]; then
    mkdir -p "$LOTUS/notesapi14"
    unzip -q -d "$LOTUS/notesapi14" *.zip
    mkdir -p "$LOTUS/notesapi14/lib/linux64"
    mv "$LOTUS/notesapi14/lib/"*.o "$LOTUS/notesapi14/lib/linux64"

  else
    unzip -q -d "$LOTUS" *.zip */include/*
    unzip -q -d "$LOTUS" *.zip */lib/linux64/*
  fi

  rm -f *.zip
  cd $LOTUS

  # sym link current sdk
  NOTES_SDK_DIR=$(find . -maxdepth 1 -name "notesapi1*")
  ln -s notesapi* notesapi

  header "Install gcc and gcc++ compilers"
  install_packages gcc g++ gcc-c++ make binutils

  # On Photon OS glibc includes are separate
  if [ -e /etc/photon-release ]; then
    install_packages glibc-devel
  fi

  # Update notes user's profile
  local NOTES_BASH_PROFIL=/home/notes/.bashrc
  echo >> $NOTES_BASH_PROFIL
  echo "# -- Begin Notes C-API environment vars --" >> $NOTES_BASH_PROFIL
  echo "export LOTUS=$LOTUS" >> $NOTES_BASH_PROFIL
  echo "export Notes_ExecDirectory=$LOTUS/notes/latest/linux" >> $NOTES_BASH_PROFIL
  echo "export LD_LIBRARY_PATH=$Notes_ExecDirectory" >> $NOTES_BASH_PROFIL
  echo "export INCLUDE=$LOTUS/notesapi/include" >> $NOTES_BASH_PROFIL
  echo "# -- End Notes C-API environment vars --" >> $NOTES_BASH_PROFIL
  echo >> $NOTES_BASH_PROFIL

  echo
  echo Installed $ADDON_NAME
  echo

  cd $CURRENT_DIR
}

install_domino_restapi()
{
  local ADDON_NAME=domrestapi
  local ADDON_VER=$1
  local REST_API_INSTALLER=

  if [ -z "$ADDON_VER" ]; then
    return 0
  fi

  header "$ADDON_NAME Installation"

  get_download_name $ADDON_NAME $ADDON_VER

  header "Installing $ADDON_NAME $ADDON_VER"

  download_and_check_hash "$DownloadFrom" "$DOWNLOAD_NAME" domino_restapi

  CURRENT_DIR=$(pwd)

  cd "$DOMINO_DATA_PATH"
  # Append the servertask line to notes.ini, because Keep installer needs it to detect the server
  echo "servertasks=" >> notes.ini

  # REST API 1.0.7 and higher supports Domino V14 which switches to Java 17 instead of Java 8.
  # Therefore two different installers are shipped for Domino 14 and earlier versions

  if [ -e "$CURRENT_DIR/domino_restapi/restapiInstall.jar" ]; then
    log_space "Older REST API for Domino 12 detected"
    REST_API_INSTALLER=$CURRENT_DIR/domino_restapi/restapiInstall.jar
  else

    # Check if JVM version is still Java 8
    local JAVA8_FOUND=$($Notes_ExecDirectory/jvm/bin/java -version 2>&1 | grep "1.8.0")

    if [ -z "$JAVA8_FOUND" ]; then
      log_space "Domino 14 Java 17 or higher detected"
      if [ -e "$CURRENT_DIR/domino_restapi/restapiInstall-r14.jar" ]; then
        REST_API_INSTALLER=$CURRENT_DIR/domino_restapi/restapiInstall-r14.jar
      else
        REST_API_INSTALLER=$CURRENT_DIR/domino_restapi/restapiInstall-r12.jar
      fi
    else
      log_space "Domino 11/12 Java 8 detected"
      if [ -e "$CURRENT_DIR/domino_restapi/restapiInstall-r12.jar" ]; then
        REST_API_INSTALLER=$CURRENT_DIR/domino_restapi/restapiInstall-r12.jar
      else
        REST_API_INSTALLER=$CURRENT_DIR/domino_restapi/restapiInstall.jar
      fi
    fi

    if [ ! -e "$REST_API_INSTALLER" ]; then
       log_error "Cannot find Domino REST API Installer [$REST_API_INSTALLER]!!!"
       echo "-------------------------"
       ls $CURRENT_DIR/domino_restapi
       echo "-------------------------"
       exit 1
    fi

  fi

  "$Notes_ExecDirectory/jvm/bin/java" -jar "$REST_API_INSTALLER" -d="$DOMINO_DATA_PATH" -i="$DOMINO_DATA_PATH/notes.ini" -r="/opt/hcl/restapi" -p="$Notes_ExecDirectory" -a -s > $INST_RESTAPI_LOG 2>&1

  if [ "$?" = "0" ]; then
    log_space Installed $ADDON_NAME
  else
    log_error "Domino REST API Installation failed!!!"
    exit 1
  fi

  check_file_str "$INST_RESTAPI_LOG" "$RESTAPI_STRING_OK"

  if [ "$?" = "1" ]; then
    echo
    log_ok "Domino REST API installed successfully"

  else
    dump_file "$INST_RESTAPI_LOG"
    log_error "Domino REST API Installation failed!!!"
    exit 1
  fi

  cd $CURRENT_DIR
}


container_set_timezone()
{
  if [ -z "$DOCKER_TZ" ]; then
    return 0
  fi

  CURRENT_TZ=$(readlink /etc/localtime)
  SET_TZ=/usr/share/zoneinfo/$DOCKER_TZ

  if [ "$CURRENT_TZ" = "$SET_TZ" ]; then
    log_space "Timezone [$DOCKER_TZ] already set"
    return 0
  fi

  if [ ! -e "$SET_TZ" ]; then
    log_space "Cannot read timezone [$SET_TZ] -- Timezone not changed"
    return 1
  fi

  log_space "Timezone set to [$DOCKER_TZ]"
  ln -sf "$SET_TZ" /etc/localtime

  return 0
}

set_ini_var_if_not_set()
{
  local file=$1
  local var=$2
  local new=$3

  if [ ! -e "$file" ]; then
    echo "Notes.ini [$file] not found! when adding [$var] = [$new]"
    return 0
  fi

  # Check if entry exists empty. if not present append new entry

  local found=$(grep -i "^$var=" $file)
  if [ -z "$found" ]; then
    echo $var=$new >> $file
  fi

  return 0
}

set_default_notes_ini_variables()
{
  # Avoid Domino Directory Design Update Prompt
  set_ini_var_if_not_set $DOMINO_DATA_PATH/notes.ini "SERVER_UPGRADE_NO_DIRECTORY_UPGRADE_PROMPT" "1"

  # Allow server names with dots and undercores
  set_ini_var_if_not_set $DOMINO_DATA_PATH/notes.ini "ADMIN_IGNORE_NEW_SERVERNAMING_CONVENTION" "1"

  # Enable remote disk stats for container by default
  set_ini_var_if_not_set $DOMINO_DATA_PATH/notes.ini "EnableRemoteDiskStats" "1"
}

install_perl()
{
  # Temporary install perl for installers if not already installed

  if [ -e /usr/bin/perl ]; then
    return 0
  fi

  if [ -n "$NO_PERL_INSTALL" ]; then
    return 0
  fi

  header "Installing perl"

  if [ -e /etc/photon-release ]; then
    install_package perl
    return 0
  fi

  if [ -x /usr/bin/zypper ]; then
    install_package perl
    return 0
  fi

  install_package perl-libs

  # Mark perl for uninstall
  UNINSTALL_PERL_AFTER_INSTALL=yes
}

remove_perl()
{
  # Removing perl if temporary installed

  if [ ! "$UNINSTALL_PERL_AFTER_INSTALL" = "yes" ]; then
    return 0
  fi

  header "Uninstalling perl"
  remove_package 'perl-*'
}

install_domino_installer_only_packages()
{
  install_packages cpio
}

remove_domino_installer_only_packages()
{
  remove_packages cpio
}

install_startscript()
{

  # Install start script version included in the repository
  if [ -z "$STARTSCRIPT_VER" ]; then

    header "Installing Start Script"

    # Run start script installer
    cd $INSTALL_DIR/startscript
    ./install_script

  else

    header "Installing Start Script $STARTSCRIPT_VER"
  
    cd $INSTALL_DIR
    get_download_name startscript $STARTSCRIPT_VER
    download_and_check_hash "$DownloadFrom" "$DOWNLOAD_NAME"
    cd domino-startscript
    ./install_script
  fi

  if [ -n "$BORG_INSTALL" ]; then
    header "Installing Domino Borg Backup integration"
    # Install Borg Backup scripts
    ./install_borg
  fi

  cd $INSTALL_DIR
  remove_directory domino-startscript

}

install_k8s_runas_user_support()
{
  if [ ! "$K8S_RUNAS_USER_SUPPORT" = "yes" ]; then
    return 0
  fi

  header "Installing K8s runAsUser support"

  cd $INSTALL_DIR

  install_packages gcc make
  make

  install_file nuid2pw "$DOMDOCK_SCRIPT_DIR/nuid2pw" root root 4550

  if [ ! -e $DOMDOCK_SCRIPT_DIR/nuid2pw ]; then
    echo "Cannot install nuid2pw (K8s runAsUser support)!"
    exit 1
  fi

  log_space "K8s runAsUser support installed"
}


harden_binary_dir()
{
  header "Hardening binary directory"

  chmod 555 $Notes_ExecDirectory/bindsock
  setcap 'cap_net_bind_service=+ep' $Notes_ExecDirectory/bindsock
}

check_build_options()
{

  local NoHardenBinDir=

  for b in $BUILD_SCRIPT_OPTIONS; do

    case "$b" in
      -NoHardenBinDir)
        NoHardenBinDir=yes
        ;;

      *)
        log_error "Invalid build option [$b] specified!"
        exit 1
        ;;
    esac

  done

  if [ "$NoHardenBinDir" = "yes" ]; then
   echo "Info: Not hardening for binary directory!"
  else
    harden_binary_dir
  fi

  return 0
}

set_security_limits()
{
  if [ "$FIRST_TIME_SETUP" = "1" ]; then
    # Set security limits for pam modules (su needs it)
    echo >> /etc/security/limits.conf
    echo '# -- Begin Changes Domino --' >> /etc/security/limits.conf
    echo '* soft nofile 80000' >> /etc/security/limits.conf
    echo '* hard nofile 80000' >> /etc/security/limits.conf
    echo '# -- End Changes' >> /etc/security/limits.conf
    echo >> /etc/security/limits.conf
  fi
}

# --- Main Install Logic ---

export DOMINO_USER=notes
export DOMINO_GROUP=notes

header "Environment Setup"

echo "INSTALL_DIR           = [$INSTALL_DIR]"
echo "DownloadFrom          = [$DownloadFrom]"
echo "Product               = [$PROD_NAME]"
echo "Version               = [$PROD_VER]"
echo "Fixpack               = [$PROD_FP]"
echo "InterimsFix/Hotfix    = [$PROD_HF]"
echo "DOMLP_VER             = [$DOMLP_VER]"
echo "DOMRESTAPI_VER        = [$DOMREST_VER]"
echo "DominoResponseFile    = [$DominoResponseFile]"
echo "DominoVersion         = [$DominoVersion]"
echo "DominoUserID          = [$DominoUserID]"
echo "LinuxYumUpdate        = [$LinuxYumUpdate]"
echo "DOMINO_LANG           = [$DOMINO_LANG]"
echo "VERSE_VERSION         = [$VERSE_VERSION]"
echo "NOMAD_VERSION         = [$NOMAD_VERSION]"
echo "TRAVELER_VERSION      = [$TRAVELER_VERSION]"
echo "LEAP_VERSION          = [$LEAP_VERSION]"
echo "CAPI_VERSION          = [$CAPI_VERSION]"
echo "LINUX_PKG_ADD         = [$LINUX_PKG_ADD]"
echo "STARTSCRIPT_VER       = [$STARTSCRIPT_VER]"
echo "K8S_RUNAS_USER        = [$K8S_RUNAS_USER_SUPPORT]"
echo "SPECIAL_CURL_ARGS     = [$SPECIAL_CURL_ARGS]"
echo "BUILD_SCRIPT_OPTIONS  = [$BUILD_SCRIPT_OPTIONS]"


LINUX_VERSION=$(cat /etc/os-release | grep "VERSION_ID="| cut -d= -f2 | xargs)
LINUX_PRETTY_NAME=$(cat /etc/os-release | grep "PRETTY_NAME="| cut -d= -f2 | xargs)
LINUX_ID=$(cat /etc/os-release | grep "^ID="| cut -d= -f2 | xargs)

# Show current OS version
if [ -n "$LINUX_PRETTY_NAME" ]; then
  header "$LINUX_PRETTY_NAME"
fi

# This logic allows incremental installs for images based on each other (e.g. 12.0.1 -> 12.0.1FP1)
if [ -e $LOTUS ]; then
  FIRST_TIME_SETUP=0
  header "!! Incremental install based on exiting Domino image !!"
else
  FIRST_TIME_SETUP=1
fi

if [ "$FIRST_TIME_SETUP" = "1" ]; then

  # Add notes user
  if [ -z "$DominoUserID" ]; then
    useradd $DOMINO_USER -U -m
  else
    useradd $DOMINO_USER -U -m -u $DominoUserID
  fi

  # Set user local if configured
  if [ -n "$DOMINO_LANG" ]; then
    echo "export LANG=$DOMINO_LANG" >> /home/$DOMINO_USER/.bash_profile
  fi

  # This alias is really missing ..
  echo "alias ll='ls -l'" >> /home/$DOMINO_USER/.bashrc

else

  # Check for existing user's group and overwrite (for base images with different group - like root)
  export DOMINO_GROUP=$(id -gn "$DOMINO_USER")

  # Don't install perl for Domino installer
  NO_PERL_INSTALL=yes
fi

# Allow world full access to the main directories to ensure all mounts work.
# Those directories might get replaced with mount points or re-created on startup of the container when /local mount is used.
# Ensure only root can write into the script directory!

# If inheriting an existing installation, it's important to ensure /local has the right permissions root:root including all permissions
# Without the full permissions mounts to sub directories don't work if specifying different users

if [ -e "/local" ]; then
  chown root:root /local
  chmod 777 /local
fi

if [ -e "$DOMINO_DATA_PATH" ]; then
  chmod $DIR_PERM "$DOMINO_DATA_PATH"
fi

# Ensure this directories are owned by root and nobody else can write to the directory
create_directory $DOMDOCK_DIR root root 755
create_directory $DOMDOCK_SCRIPT_DIR root root 755

#Owned by root but writable for everyone
create_directory $DOMDOCK_LOG_DIR root root 777

# Needs full permissions for mount points
create_directory /local root root 777

# All other directories are owned by Domino
create_directory "$DOMINO_DATA_PATH" $DOMINO_USER $DOMINO_GROUP $DIR_PERM
create_directory /local/translog $DOMINO_USER $DOMINO_GROUP $DIR_PERM
create_directory /local/daos $DOMINO_USER $DOMINO_GROUP $DIR_PERM
create_directory /local/nif $DOMINO_USER $DOMINO_GROUP $DIR_PERM
create_directory /local/ft $DOMINO_USER $DOMINO_GROUP $DIR_PERM
create_directory /local/backup $DOMINO_USER $DOMINO_GROUP $DIR_PERM
create_directory /local/restore $DOMINO_USER $DOMINO_GROUP $DIR_PERM

if [ -n "$BORG_INSTALL" ]; then
  create_directory /local/borg $DOMINO_USER $DOMINO_GROUP $DIR_PERM
fi

container_set_timezone

# Check if HCL Domino image is already installed -> In that case just set version
if [ -e "/tmp/notesdata.tbz2" ]; then

  set_domino_version ver
  FIRST_TIME_SETUP=
  SkipDominoMoveInstallData=yes

  # Set link to install data
  ln -s /tmp/notesdata.tbz2 $DOMDOCK_DIR/install_data_domino.taz

  # Domino is already installed. No perl needed
  NO_PERL_INSTALL=yes
fi

install_perl
install_domino_installer_only_packages

cd "$INSTALL_DIR"

# Download updated software.txt file if available
download_file_ifpresent "$DownloadFrom" software.txt "$INSTALL_DIR"

if [ "$FIRST_TIME_SETUP" = "1" ]; then
  case "$PROD_NAME" in
    domino)
      install_domino
      ;;

    *)
      log_error "Unknown product [$PROD_NAME] - Terminating installation"
      exit 1
      ;;
  esac
fi

# Install Verse if requested
install_verse "$VERSE_VERSION"

# Install Nomad Server if requested
install_nomad "$NOMAD_VERSION"

# Install C-API if requested
install_capi "$CAPI_VERSION"

# Install Domino REST API if requested
install_domino_restapi "$DOMRESTAPI_VER"

# Install Traveler Server if requested
install_traveler "$TRAVELER_VERSION"

# Install Domino Leap if requested
install_leap "$LEAP_VERSION"


remove_perl

# Install Domino start script
install_startscript

# Explicitly set container environment to ensure any container implementation works
export CONTAINER_ENV=any

# Allow gdb to use sys ptrace --> Needs to be granted explicitly on some container platforms

if [ -x /usr/bin/gdb ]; then
  if [ ! -L /usr/bin/gdb ]; then
    echo "symbolic link"
    setcap 'cap_sys_ptrace+ep' /usr/bin/gdb
    echo "Setting cap_sys_ptrace for /usr/bin/gdb"
  fi
fi

# Some platforms like UBI use a sym link for gdb
if [ -x /usr/libexec/gdb ]; then
  if [ ! -L /usr/libexec/gdb ]; then
    setcap 'cap_sys_ptrace+ep' /usr/libexec/gdb
    echo "Setting cap_sys_ptrace for /usr/libexec/gdb"
  fi
fi

# If gdb.minimal is installed, set pstack capabilities
if [ -x /usr/bin/gdb.minimal ]; then
    setcap 'cap_sys_ptrace+ep' /usr/bin/gdb.minimal
    echo "Setting cap_sys_ptrace for /usr/bin/gdb.minimal"
fi


# Install Setup Files and Docker Entrypoint

header "Final Steps & Configuration"

# Copy pre-start configuration
install_file "$INSTALL_DIR/domino_prestart.sh" "$DOMDOCK_SCRIPT_DIR/domino_prestart.sh" root root 755

# Copy script lib used by other installers
install_file "$INSTALL_DIR/script_lib.sh" "$DOMDOCK_SCRIPT_DIR/script_lib.sh" root root 755

# Copy Docker specific start script configuration if provided
install_file "$INSTALL_DIR/rc_domino_config" "$DOMINO_DATA_PATH/rc_domino_config" root root 644
install_file "$INSTALL_DIR/entrypoint.sh" "/entrypoint.sh" root root 755

# Install Data Directory Copy File
install_file "$INSTALL_DIR/domino_install_data_copy.sh" "$DOMDOCK_SCRIPT_DIR/domino_install_data_copy.sh" root root 755

# Install health check script
install_file "$INSTALL_DIR/healthcheck.sh" "/healthcheck.sh" root root 755

# add symbolic link to old location for now
ln -s "/healthcheck.sh" "/domino_docker_healthcheck.sh"

install_k8s_runas_user_support

# set security limits late in the installation process to avoid conflicts with limited resources available in some container environments like Podman when switching users
set_security_limits

# Set notes.ini variables needed
set_default_notes_ini_variables

# Rename notes.ini to notes.ini.install to allow full extraction of the domino.taz.
# Separate logic to deploy notes.ini from notes.ini.install if not found
mv "$DOMINO_DATA_PATH/notes.ini" "$DOMINO_DATA_PATH/notes.ini.install"

# --- Cleanup Routines to reduce image size ---

# Remove Fixpack/Hotfix backup files
find $Notes_ExecDirectory -maxdepth 1 -type d -name "120**" -exec rm -rf {} \; 2>/dev/null
find $Notes_ExecDirectory -maxdepth 1 -type d -name "110**" -exec rm -rf {} \; 2>/dev/null

# Remove not needed domino/html data to keep image smaller
find $DOMINO_DATA_PATH/domino/html -name "*.dll" -exec rm -rf {} \; 2>/dev/null
find $DOMINO_DATA_PATH/domino/html -name "*.msi" -exec rm -rf {} \; 2>/dev/null

remove_directory "$DOMINO_DATA_PATH/domino/html/download/filesets"
remove_directory "$DOMINO_DATA_PATH/domino/html/help"

# Remove Domino 12 and higher uninstaller --> we never uninstall but rebuild from scratch
remove_directory "$Notes_ExecDirectory/_HCL Domino_installation"

# Remove InstallAnywhere uninstaller JVMs (name differs depending on version)
remove_directory "$Notes_ExecDirectory/IA_jre"
remove_directory "$Notes_ExecDirectory/jre"

# Remove Verse add-on installer ZIP
remove_directory "$Notes_ExecDirectory/addons/verse"

# Create missing links

create_startup_link kyrtool
create_startup_link dbmt
install_res_links

# Remove tune kernel binary, because it cannot be used in container environments
remove_file "$LOTUS/notes/latest/linux/tunekrnl"

# In some versions the Tika file is also in the data directory.
remove_file $DOMINO_DATA_PATH/tika-server.jar

check_build_options

# Ensure permissons are set correctly for data directory
chown -R $DOMINO_USER:$DOMINO_GROUP $DOMINO_DATA_PATH

# Now export the lib path just in case for Domino to run
export LD_LIBRARY_PATH=$Notes_ExecDirectory:$LD_LIBRARY_PATH

# If configured, move data directory to a compressed tar file

if [ "$SkipDominoMoveInstallData" = "yes" ]; then
  header "Skipping notesdata compression for incremental build"

else
  DOMDOCK_INSTALL_DATA_TAR=$DOMDOCK_DIR/install_data_domino.taz

  if [ "$FIRST_TIME_SETUP" = "1" ]; then
    header "Moving install data $DOMINO_DATA_PATH -> [$DOMDOCK_INSTALL_DATA_TAR]"

    cd $DOMINO_DATA_PATH
    remove_file "$DOMDOCK_INSTALL_DATA_TAR"
    tar -czf "$DOMDOCK_INSTALL_DATA_TAR" .

    remove_directory "$DOMINO_DATA_PATH"
    create_directory "$DOMINO_DATA_PATH" $DOMINO_USER $DOMINO_GROUP $DIR_PERM
  fi
fi

# Remove gcc compiler if no C-API toolkit is installed
# gdb installs gcc on most platforms and gcc can be up to 100 MB

if [ -z "$CAPI_VERSION" ]; then
  remove_package gcc make
fi

# Remove installer only required packages
remove_domino_installer_only_packages

# Cleanup repository cache to save space
clean_linux_repo_cache

header "Successfully completed installation!"

exit 0
