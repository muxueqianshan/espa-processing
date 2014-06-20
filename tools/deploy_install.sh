#!/bin/bash
#
#
#
#
# Name: deploy_install.sh
#
# Description: Software deployment installation script for ESPA/Hadoop architecture
#
# Author: Adam Dosch
#
# Creation Date: 06-21-2011
#
#
#############################################################################################################################
# Change	Date		Author			Description
#############################################################################################################################
#  001		06-21-2011	Adam Dosch		Initial Release
#  002		01-17-2013	Adam Dosch		Updating deployment script 
#  003		07-22-2013	Adam Dosch		Adding parameter functionality for tag release, dot-file config file
#							to override anything hard coded, and insertion of database creds 
#							from dotfile in homedir (yish but will work for now)
#  004		07-31-2013	Adam Dosch		Added local clean-up for DB_CRED_SCRIPT cleanup
#  005		04-29-2014	Adam Dosch		Rewrite of deployment script to add '--mode' to specify 'devel|prod'
#							Adding '--tier' to specify 'processing|web|app|maintenance' to work
#							with new app deployment with uwsgi
#							Adding new function for stdout writing when VERBOSE is enabled
#							Removing --remotehost flag
#  006		05-08-2014	Adam Dosch		Adding more deployment logic for uwsgi
#							Adding CHECKOUT_TYPE to do checkout vs export in SVN for MODE
#  007		06-06-2014	Adam Dosch		Adding set_user and finishing deployment logic
#  008		06-18-2014	Adam Dosch		Adding logic for SVN repository structure changes where 'tags/' is
#							is being renamed to 'releases/' and we are adding 'testing/' for the
#							'dev' and 'tst' environments.  'releases/' will be for production.
#							Redoing relese_validation() checking outside of parameter case
#							statement and moving out the parameter setup so we have all parameters
#							to pick the right svn structure area to look for version
#							Adding SVN_TAGAREA to set tag area out of repository
#							Adding SVN_TAGAREA setting in set_checkout() function
#
#############################################################################################################################

declare -r PINGBIN="/bin/ping"

declare -r SSHBIN="/usr/bin/ssh -q"

declare -r SCPBIN="/usr/bin/scp -q"

declare -r SVNBIN="/usr/bin/svn"

STAMP=$( date +'%m%d%y-%H%M%S' )

SVN_WORKING_DIR=${HOME}/tmp

APP_FILE="/web/espa_web/espa-uwsgi.ini"

SVN_HOST="http://espa.googlecode.com"

SVN_BASE="/svn"

SVN_TAGAREA=""

CHECKOUT_TYPE="co"

declare RELEASE

declare TIER="all"

declare TIERS="app maintenance processing"

declare MODE

declare DEPLOYUSER

declare MODES="tst devel prod"

declare VERBOSE=1

declare DELETE_PRIOR_RELEASES=1

function print_usage
{
   echo
   echo " Usage: $0 --mode=[prod|tst|devel] --tier=[app|maintenance|processing|all]  --release=<espa-n.n.n-release> [-v|--verbose] [-d|--delete-prior-releases]"
   echo

   exit 1
}

function mode_validation
{
   # $1 - mode from parameter

   for valid_mode in $MODES
   do
      if [ "$valid_mode" == "$1" ]; then
         echo $1
         break
      fi
   done
}

function release_validation
{
   # $1 - release from parameter
   # $2 - svn tag area based off 'mode'

   # Let's make sure it exists in SVN or bail out too
   for valid_tag in $( ${SVNBIN} list ${SVN_HOST}${SVN_BASE}/$2 )
   do
      if [ "$valid_tag" == "$1/" ]; then
         echo $1
         break
      fi
   done
}

function tier_validation
{
   #$1 - tier from parameter

   for valid_tier in $TIERS all
   do
      if [ "$valid_tier" == "$1" ]; then
         echo $1
         break
      fi
   done
}

function write_stdout
{
   # $1 -> mode
   # $2 -> message body
   TIMESTAMP=$(  date +'%b %d %H:%M:%S' )

   echo "${TIMESTAMP} deployment $1: $2"   
}

function set_checkout
{
   # $1 -> mode
   case $1 in
     "prod")
        SVN_TAGAREA="/releases"
        CHECKOUT_TYPE="export"
        ;;
     "tst")
        SVN_TAGAREA="/testing"
        CHECKOUT_TYPE="co"
        ;;
     *)
        SVN_TAGAREA="/testing"
        CHECKOUT_TYPE="co"
        ;;
   esac
}

function set_user
{
   # $1 -> mode
   case $1 in
     "prod")
        DEPLOYUSER="espa"
        ;;
     "tst")
        DEPLOYUSER="espadev"
        ;;
     *)
        DEPLOYUSER="espadev"
        ;;
   esac
}

function deploy_tier
{

   #$1 - tier
   #$2 - mode

   mode=$2

   declare -A tierhosts

   tierhosts[tst-app]="l8srlscp13"
   tierhosts[tst-maintenance]="l8srlscp01"
   tierhosts[tst-processing]="l8srlscp08"

   tierhosts[devel-app]="l8srlscp16"
   tierhosts[devel-maintenance]="l8srlscp16"
   tierhosts[devel-processing]="l8srlscp16"
   
   tierhosts[prod-app]="l8srlscp14"
   tierhosts[prod-maintenance]="l8srlscp01"
   tierhosts[prod-processing]="l8srlscp05"

   if [ "$1" == "all" ]; then
      tiers="$TIERS"
   else
      tiers=$1
   fi

   for tier in $tiers
   do
      lookup="${mode}-${tier}"

      for server in ${tierhosts[${lookup}]}
      do
         [[ $VERBOSE -eq 0 ]] && write_stdout "$MODE" "Starting deployment for: $server"
   
         # Is host up? (Crude input santization might be needed? This should catch malformed FQDN or invalid hosts)
         [[ $VERBOSE -eq 0 ]] && write_stdout "$MODE" "Pinging $server ... "
   
         ${PINGBIN} -q -c2 ${server} &> /dev/null

         if [ $? -eq 0 ]; then
            [[ $VERBOSE -eq 0 ]] && write_stdout "${MODE}" "Server alive, continuing."
   
            # If we've chosen to remove releases, let's do that first, since we auto-backup prior to release below in the deployment
            [[ $DELETE_PRIOR_RELEASES -eq 0 ]] && write_stdout "$MODE" "Removing all prior code deployments matching: ${SVN_WORKING_DIR}.deploy-*" && ${SSHBIN} -t ${server} "rm -rf ${SVN_WORKING_DIR}.deploy-*" &> /dev/null
   
            # Do code deployment on server with SSH
            [[ $VERBOSE -eq 0 ]] && write_stdout "$MODE" "Deploying ESPA release $RELEASE to $SVN_WORKING_DIR on $server"

            # Create espa-site dir if it doesn't exist
            ${SSHBIN} -t ${server} "mkdir -p ~/espa-site"
 
            if [ "$tier" == "app" ]; then
               write_stdout "$MODE" "Performing 'app' tier deployment commands"
               ${SSHBIN} -t ${server} "mv $SVN_WORKING_DIR ${SVN_WORKING_DIR}.deploy-${STAMP}; mkdir -p $SVN_WORKING_DIR; cd $SVN_WORKING_DIR; svn ${CHECKOUT_TYPE} ${SVN_HOST}${SVN_BASE}/${SVN_TAGAREA}/${RELEASE} .; find $SVN_WORKING_DIR -type f -name \"*.pyc\" -exec rm -rf '{}' \;" &> /dev/null
            elif [ "$tier" == "maintenance" ]; then
               write_stdout "$MODE" "Performing 'maintenance' tier deployment commands"
               ${SSHBIN} -t ${server} "mv $SVN_WORKING_DIR ${SVN_WORKING_DIR}.deploy-${STAMP}; mkdir -p $SVN_WORKING_DIR; cd $SVN_WORKING_DIR; svn ${CHECKOUT_TYPE} ${SVN_HOST}${SVN_BASE}/${SVN_TAGAREA}/${RELEASE} .; find $SVN_WORKING_DIR -type f -name \"*.pyc\" -exec rm -rf '{}' \;" &> /dev/null
            elif [ "$tier" == "processing" ]; then
               write_stdout "$MODE" "Performing 'processing' tier deployment commands"
               ${SSHBIN} -t ${server} "mv $SVN_WORKING_DIR ${SVN_WORKING_DIR}.deploy-${STAMP}; mkdir -p $SVN_WORKING_DIR; cd $SVN_WORKING_DIR; svn ${CHECKOUT_TYPE} ${SVN_HOST}${SVN_BASE}/${SVN_TAGAREA}/${RELEASE} .; find $SVN_WORKING_DIR -type f -name \"*.pyc\" -exec rm -rf '{}' \;" &> /dev/null
            fi

            # Create necessary soft-linkage to deploy directory
            ${SSHBIN} -t ${server} "cd ~/espa-site; ln -f -s ../tmp/* ."

            # If app tier, update soft-link for uwsgi and re-touch file to reload
            if [ "$tier" == "app" ]; then
               write_stdout "$MODE" "Performing app tier environment customization and app deployment"
               # Update uwsgi with correct deploy user home path
               ${SSHBIN} -t ${server} "sed -i -r -e \"s~/home/[a-zA-Z]+/~/home/${DEPLOYUSER}/~g\" ${SVN_WORKING_DIR}/${APP_FILE}"

               # Uncomment ESPA_ENV and set proper environment
               ${SSHBIN} -t ${server} "sed -i -r -e \"s~^\#*env = ESPA_ENV=.*~env = ESPA_ENV=${MODE}~\" ${SVN_WORKING_DIR}/${APP_FILE}"

               # Uncomment ESPA_CONFIG_FILE
               ${SSHBIN} -t ${server} "sed -i -r -e \"s~^\#*env = ESPA_CONFIG_FILE=.*~env = ESPA_CONFIG_FILE=/home/${DEPLOYUSER}/.cfgnfo~\" ${SVN_WORKING_DIR}/${APP_FILE}"

               # Update uid/gid to run as deploy user
               ${SSHBIN} -t ${server} "sed -i -r -e \"s~^gid = .*~gid = ${DEPLOYUSER}~g\" ${SVN_WORKING_DIR}/${APP_FILE}"
               ${SSHBIN} -t ${server} "sed -i -r -e \"s~^uid = .*~uid = ${DEPLOYUSER}~g\" ${SVN_WORKING_DIR}/${APP_FILE}"
              
               # Logfile locatoins permissions
               ${SSHBIN} -t ${server} "chmod 777 ${SVN_WORKING_DIR}/web/espa_web/logs"
 
               # Deploy uwsgi .ini
               ${SSHBIN} -t ${server} "\rm -rf /opt/cots/uwsgi/apps/$(basename ${APP_FILE}); ln -s ${SVN_WORKING_DIR}/${APP_FILE} /opt/cots/uwsgi/apps/; touch ${SVN_WORKING_DIR}/${APP_FILE}"
            fi
   
            [[ $VERBOSE -eq 0 ]] && write_stdout "$MODE" "Deployment complete for $server"
         else
            # Ping failed on host, bail out!
            [[ $VERBOSE -eq 0 ]] && write_stdout "$MODE" "Ping failed on server.  Not up?  Exiting."
            exit 1
         fi
      done
   done

}

##############################################################################################################################
#                         START OF SCRIPT - DO NOT EDIT BELOW UNLESS YOU KNOW WHAT YOU ARE DOING
##############################################################################################################################

if [ $# -ge 2 -a $# -le 5 ]; then

   for param in $@
   do
      case $param in
         --mode=*)
            MODE=$( echo $param | cut -d= -f2 | sed -r -e "s/[\"\']//g" | tr A-Z a-z )

            response=$( mode_validation "$MODE" )

            if [ -z "$response" ]; then
               echo -e "\nInvalid mode: $MODE -- provide correct mode to continue"
               print_usage
            fi
            ;;
         --tier=*)
            TIER=$( echo $param | cut -d= -f2 | sed -r -e "s/[\"\']//g" | tr A-Z a-z )

            response=$( tier_validation "$TIER" )
            if [ -z "$response" ]; then
               echo -e "\nInvalid tier: $TIER -- provide corect tier to continue or use 'all'"
               print_usage
            fi
            ;;
         -v|--verbose)
            VERBOSE=0
            [[ $VERBOSE -eq 0 ]] && write_stdout "$MODE" "Verbose mode enabled"
            ;;
         --release=*)
            RELEASE=$( echo $param | cut -d= -f2 | sed -r -e "s/[\"\']//g" | tr A-Z a-z )
            ;;
         -d|--delete-prior-releases)
            DELETE_PRIOR_RELEASES=0
            ;;
         *)
            echo
            echo "Invalid option: $param"
            echo
            print_usage
            ;;
      esac
   done

   # Hack to check for mandatory options
   if [ -z "$MODE" -o -z "$RELEASE" ]; then
      print_usage
   else
      [[ $VERBOSE -eq 0 ]] && write_stdout "$MODE" "Passed mandatory parameter check.  We have everything to continue deployment."
   fi

   # Set checkout svh tagarea type
   set_checkout "$MODE"

   # Validate release against SVN repo
   response=$( release_validation "$RELEASE" "$SVN_TAGAREA" )

   if [ -z "$response" ]; then
      echo -e "\nInvalid release: $RELEASE -- Either invalid format or doesn't exist in SVN repo"
      print_usage
   fi

   # Set user
   set_user "$MODE"

   # Deploy tier
   deploy_tier "$TIER" "$MODE" 

else
   print_usage
fi