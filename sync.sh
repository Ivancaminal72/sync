#!/bin/bash
#WHY sync.sh? to do specific/reliable transfers when connection didn't allow for "fluid" X11 edition of remote files
#WARN: Replicate modifications in excluded dirs (find . | egrep "*$excluded*" --color)
#REQUIRES: "inotifywait" (sudo apt install inotify-tools)

#Exit if error
set -e

#Initial blacklist
blacklist=(
".gitignore"
".git/"
".git2/"
"build/"
"bin/"
"devel/"
"*.pyc"
"__pycache__"
".fuse*"
".nfs*")


logging=true

main(){
    if [ "$1" != "" ] && [ "$2" != "" ] && [ "$3" != "" ]; then
        hostARG=`echo $1 | awk -F= '{print tolower($1)}'`
        actionARG=`echo $2 | awk -F= '{print tolower($1)}'`
        projectARG=`echo $3 | awk -F= '{print tolower($1)}'`

        #Host
        case $hostARG in
            "gpi")
                host="gpi"
                address="icaminal@calcula.tsc.upc.edu"
                ;;
            "cd6")
                host="cd6"
                address="icaminal@10.7.8.45"
                ;;
            *)
                echo "ERROR: unknown host name: \"$hostARG\""
                exit 1
                ;;
        esac

        logdirs="$HOME/syncs/$host:~/syncs" #Logging directories (LOCAL:REMOTE)

        #Project
        case $projectARG in
            "ros")
                paths="$HOME/workspace/ros_ddd:~/workspace/ros_ddd"
                ;;
            "phd")
                blacklist+=("**/corelib/include/rtabmap/core/Version.h") #custom exclude
                blacklist+=("**/corelib/src/resources/DatabaseSchema.sql")
                blacklist+=("/opencv")
                paths="$HOME/workspace/phd:~/workspace/phd" #paths to sync (LOCAL:REMOTE)
                ;;
            "mth")
                blacklist+=("world3d-ros/")
                paths="$HOME/workspace/mth:~/workspace/mth"
                ;;
            "do")
                paths="$HOME/workspace/doitforme:~/workspace/doitforme"
                ;;
            "imp")
                paths="$HOME/$host/important:~/important"
                logging=false
                if [[ ! $actionARG =~ g.* ]]; then
                    echo "ERROR: \"${paths%%:*}\" can only be get!"; exit -1; fi
                ;;
            "out")
                paths="$HOME/$host/outputs:~/outputs"
                maxsize="1M"
                logging=false
                if [[ ! $actionARG =~ g.* ]]; then
                    echo "ERROR: \"${paths%%:*}\" can only be get!"; exit -1; fi
                ;;
            "map")
                paths="$HOME/$host/mappings:~/mappings"
                maxsize="1000M"
                logging=false
                if [[ ! $actionARG =~ g.* ]]; then
                    echo "ERROR: \"${paths%%:*}\" can only be get!"; exit -1; fi
                ;;
            *)
                echo "ERROR: unknown project name: \"$projectARG\""
                exit 1
                ;;
        esac

        #Action
        dryrun=""
        if [[ $actionARG == *"dry" ]]; then
            dryrun="--dry-run"
            logging=false
        fi

        if [[ ! -d "${logdirs%%:*}" ]] && $logging; then mkdir -p "${logdirs%%:*}"; fi

        case $actionARG in
            "g"* )
                get
                ;;
            "setloop"* | "sl"* )
                setloop true
                ;;
            "s"* )
                setloop false
                ;;
            *)
                echo "ERROR: unknown action: \"$actionARG\""
                exit 1
                ;;
        esac

    else
        echo "Usage: $0 host action project"
    fi
}

get(){

    create_excludes #Create array of excludes from blacklist

    #LOG start
    if $logging; then
        printf "$host " >> ${logdirs%%:*}/$projectARG.txt
        trap "printf ' Exit with error\n' >> ${logdirs%%:*}/$projectARG.txt" ERR #Log ERROR exits
        trap "printf ' Exit by USER\n' >> ${logdirs%%:*}/$projectARG.txt; trap - ERR" INT #Log USER exits (and reset ERR)
    fi

    #Get remotedir/folname
    echo -e "\n\n****************** Geting $host ${paths##*:} ******************\n"
    rsync -rltgoDv $dryrun --delete -e 'ssh -p 2225' --progress ${excludes[*]} \
    ${address}:${paths##*:}/ ${paths%%:*}/
    if (($? == 0)); then echo -e "OK!  ${paths##*:}\n"; fi

    #LOG end
    if $logging; then
        echo '--> '`cat /etc/hostname`'    '`date` >> ${logdirs%%:*}/$projectARG.txt

        #Upload logs to remote
        trap - INT ERR #reset signal handling to default
        rsync -rltgoDq $dryrun --delete -e 'ssh -p 2225' ${logdirs%%:*}/ ${address}:${logdirs##*:}
        if (($? == 0)); then echo -e "syncs uploaded"; fi
    fi

    date +"%T"; echo
}

setloop(){

    create_excludes #Create array of excludes from blacklist

    while true; do

        #LOG start
        if $logging; then
            printf `cat /etc/hostname` >> ${logdirs%%:*}/$projectARG.txt
            trap "printf ' Exit with error\n' >> ${logdirs%%:*}/$projectARG.txt" ERR #Log ERROR exits
            trap "printf ' Exit by USER\n' >> ${logdirs%%:*}/$projectARG.txt; trap - ERR" INT #Log USER exits (and reset ERR)
        fi

        #Set remotedir/folname
        echo -e "\n\n------------------- Set $host ${paths##*:} -------------------\n"
        rsync -rltgoDv $dryrun --delete -e 'ssh -p 2225' --progress ${excludes[*]} \
        ${paths%%:*}/ ${address}:${paths##*:}/
        if (($? == 0)); then echo -e "OK!  ${paths##*:}\n"; notify-send "$projectARG"; fi

        #LOG end
        if $logging; then
            echo " --> $host    "`date` >> ${logdirs%%:*}/$projectARG.txt

            #Upload logs to remote
            trap - INT ERR #reset signal handling to the default
            rsync -rltgoDq $dryrun --delete -e 'ssh -p 2225' ${logdirs%%:*}/ ${address}:${logdirs##*:}
            if (($? == 0)); then echo -e "syncs uploaded"; fi
        fi

        date +"%T"; echo

        #LOOPING
        if $1; then
            sleep 0.2
            #Trigger when an event occurs
            if inotifywait -q -r -e create,delete,modify,move ${paths%%:*}/; then
                continue
            else
                exit 1
            fi
        else
            exit
        fi
    done
}

create_excludes(){
    excludes=()
    for f in ${blacklist[@]}
    do
        excludes+=(--exclude $f)
    done

    if [[ ! -z $maxsize ]]; then
      excludes+=(--max-size $maxsize);
    fi
}

main "$@"
