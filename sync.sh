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
".pyc"
".*.pyc"
".fuse*"
".nfs*")


logging=true
logdirs="$HOME/syncs/gpi:~/syncs" #Logging directories (LOCAL:REMOTE)

main(){
    if [ "$1" != "" ] && [ "$2" != "" ]; then
        actionARG=`echo $1 | awk -F= '{print tolower($1)}'`
        projectARG=`echo $2 | awk -F= '{print tolower($1)}'`

        #Project
        case $projectARG in
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
                paths="$HOME/gpi/important:~/important"
                logging=false
                if [[ ! $actionARG =~ g.* ]]; then
                    echo "ERROR: \"${paths%%:*}\" can only be get!"; exit -1; fi
                ;;
            "out")
                paths="$HOME/gpi/outputs:~/outputs"
                maxsize="1M"
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
        echo "Usage: $0 action project"
    fi
}

get(){

    create_excludes #Create array of excludes from blacklist

    #LOG start
    if $logging; then
        printf "gpi " >> ${logdirs%%:*}/$projectARG.txt
        trap "printf ' Exit with error\n' >> ${logdirs%%:*}/$projectARG.txt" ERR #Log ERROR exits
        trap "printf ' Exit by USER\n' >> ${logdirs%%:*}/$projectARG.txt; trap - ERR" INT #Log USER exits (and reset ERR)
    fi

    #Get remotedir/folname
    echo -e "\n\n************* Geting gpi ${paths##*:} ****************\n"
    rsync -rltgoDv $dryrun --delete -e 'ssh -p 2225' --progress ${excludes[*]} \
    icaminal@calcula.tsc.upc.edu:${paths##*:}/ ${paths%%:*}/
    echo -e "OK!  ${paths##*:}\n"

    #LOG end
    if $logging; then
        echo '--> '`cat /etc/hostname`'    '`date` >> ${logdirs%%:*}/$projectARG.txt

        #Upload logs to remote
        trap - INT ERR #reset signal handling to default
        rsync -rltgoDq $dryrun --delete -e 'ssh -p 2225' ${logdirs%%:*}/ icaminal@calcula.tsc.upc.edu:${logdirs##*:}
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
        echo -e "\n\n---------------------- Set gpi ${paths##*:} ----------------------\n"
        rsync -rltgoDv $dryrun --delete -e 'ssh -p 2225' --progress ${excludes[*]} \
        ${paths%%:*}/ icaminal@calcula.tsc.upc.edu:${paths##*:}/
        echo -e "OK!  ${paths##*:}\n"

        #LOG end
        if $logging; then
            echo " --> gpi    "`date` >> ${logdirs%%:*}/$projectARG.txt

            #Upload logs to remote
            trap - INT ERR #reset signal handling to the default
            rsync -rltgoDq $dryrun --delete -e 'ssh -p 2225' ${logdirs%%:*}/ icaminal@calcula.tsc.upc.edu:${logdirs##*:}
            if (($? == 0)); then echo -e "syncs uploaded"; fi
        fi

        date +"%T"; echo

        #LOOPING
        if $1; then
            sleep 0.2
            #Trigger when an event occurs
            if inotifywait -r -e create,delete,modify,move ${paths%%:*}/; then
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
