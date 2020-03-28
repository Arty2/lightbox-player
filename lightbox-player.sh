#!/bin/bash
## lightbox-player.sh
## A method to play one video with different subtitles across multiple monitors or projectors.
##
## Requirements: Windows 10, Windows for Linux Subsystem, socat, bc
## 
##

VERSION=20200328-01
BEBUG=false # true: DEBUG mode enabled
BRANDED=false # true: Play intro and outro


PATH=$PATH:./mplayer # add ./mplayer directory to path

## floating point calculation functions
## via https://unix.stackexchange.com/questions/40786/
# calc() { echo "$*" | bc; } # integer calculations only
# calc() { awk "BEGIN{print $*}"; } 
calc() { echo "scale=3;$*" | bc; }
floor() { echo "$*" | cut -d "." -f1; }
# ceil()  { echo "$*" | cut -d "." -f1 + 1; }

## get PC monitor width and height
## following method only works in Windows 10
## only used in DEBUG
# DisplaySwitch.exe /extend # make sure monitors are in extend mode
# via https://stackoverflow.com/questions/25594848/batch-get-display-resolution-from-windows-command-line-and-set-variable
# MONWIDTH=$(wmic.exe desktopmonitor get screenwidth | grep -o '[0-9]\+') # alternative method
MONWIDTH=$(wmic.exe path Win32_VideoController get CurrentHorizontalResolution | grep -o '[0-9]\+')
MONHEIGHT=$(wmic.exe path Win32_VideoController get CurrentVerticalResolution | grep -o '[0-9]\+')

## get number of connected screens
## following method only works in Windows 10
# via https://www.reddit.com/r/PowerShell/comments/67no9x/detect_number_of_connected_monitorsscreens_ps40/dgrry3b/
# and https://stackoverflow.com/questions/8316649/bash-programmation-cygwin-illegal-character-m
MAXSCREENS=4 # maximum number of screens
SCREENS=$(powershell.exe '(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams | where {$_.Active -like "True"}).Active.Count' | tr -d $'\r' )
# SCREENS=1 # DEBUG
if [ $SCREENS = 1 ] # if single monitor, then enter debug mode for 4 screens
then
    SCREENS=4
    DEBUG=true
fi

## define resolution of projections
PROJWIDTH=1280
PROJHEIGHT=800
TRUESCROFFSET=0 # 2.5cm as built, set to 0
TRUESCRWIDTH=$(( 239 - 5 )) # 239cm, minus 2 * offset
TRUESCRHEIGHT=$(( 199 - 5 )) # 199cm, minus 2 * offset

## calculate calculate screen height in pixels
PPCM=$( calc "($PROJWIDTH / ($TRUESCRWIDTH - 2 * $TRUESCROFFSET))" ); # pixels per cm
SCRWIDTH=$( calc "($TRUESCRWIDTH * $PPCM)" );
SCRHEIGHT=$( calc "($TRUESCRHEIGHT * $PPCM)" );
SCROFFSET=$( calc "($TRUESCROFFSET * $PPCM)" );

# calculate top offset of screens (physical constrain)

VOFFSET=$( calc "($SCRHEIGHT - 2 * $SCROFFSET - $PROJHEIGHT - $PPCM) / ($SCREENS - 1)" ); ## - $PPCM to adjust for rounding errors

## go through the files in FILMSDIR, store the paths
## based on https://stackoverflow.com/questions/33458614/bash-dialog-dynamic-menu
FILMSDIR='./FILMS' # films' directory
FILES=($FILMSDIR/*)
# printf '%s\n' "${FILES[@]}" # DEBUG


## make a numbered menu
for i in "${!FILES[@]}"
do
    MENU[$j]="$i"
    MENU[$j + 1]="${FILES[$i]##*/}"
    j=($j+2)
done

## display a menu to select film
FILE=$(dialog --clear \
    --backtitle "lightbox-player v:"$VERSION \
    --title "" \
    --menu "Select a film, then press Enter:" \
    15 50 15 \
    "${MENU[@]}" \
    2>&1 >$(tty))

## find video files in selected directory
## look into including additional files (of same length) in the future
FILM=$(find "${FILES[$FILE]}" -type f | grep -E "\.mp4$|\.mkv$|\.mov$|\.avi$" | head -1) # | head -1 only returns the first file
if [ -z "$FILM" ] # check if empty
then # run callibration routine if no match
    FILM='./CALLIBRATION/callibration.mkv'
else # search for subtitles
    SUBTITLES=("${FILES[$FILE]}"/*.srt) 
fi

## workaround for lack of subtitles
SUBTITLES+=(0 0 0 0) # subtitles for each screen

# echo $FILM # DEBUG
# printf '%s\n' "${SUBTITLES[@]}" # DEBUG

## get width and height of video
VIDWIDTH=$(mplayer.exe -really-quiet \
    -ao null -vo null -identify -frames 0 "$FILM" | \
    grep -E 'ID_VIDEO_WIDTH' | \
    grep -o '[0-9]\+')
VIDHEIGHT=$(mplayer.exe -really-quiet \
    -ao null -vo null -identify -frames 0 "$FILM" | \
    grep -E 'ID_VIDEO_HEIGHT' | \
    grep -o '[0-9]\+')
VIDASPECT=$(( VIDWIDTH / VIDHEIGHT )) # integer, 0 if 3:4, 1 if full HD, 2 if Widescreen

## calculate top offset
TOPOFFSETS=(0 0 0 0) # initialize array
for x in $( seq 0 $(( MAXSCREENS - 1)) ); do
    TOPOFFSETS[$(( MAXSCREENS - 1 - x ))]=$( floor $( calc "$VOFFSET * $x" ) )
done
# manual adjust for placement of screens
SWAP=${TOPOFFSETS[1]}
TOPOFFSETS[1]=${TOPOFFSETS[2]}
TOPOFFSETS[2]=$SWAP
# TOPOFFSETS=(256 87 174 0) # as calculated
# 256 instead of 87*4 because of rounding error?

# printf '%s\n' "${TOPOFFSETS[@]}" # DEBUG

## display step in the terminal
echo -e "\e[103m\e[30mlightbox-player:\e[90m Playing intro...\e[0m" $(date -u)

## play intro video across all screens
## aspect ration should match the total projection size
## ; at the end of line pauses execution of following command until this line exits
if [ $BRANDED = true ]
then
    mplayer.exe -really-quiet \
        -vo direct3d -fixed-vo \
        -xy 3000 -geometry 0:0 \
        ./INTRO/intro.mp4 -loop 0;
fi

## play loop afterwards: http://lists.mplayerhq.hu/pipermail/mplayer-users/2013-July/086351.html
# mplayer.exe -vo direct3d -fixed-vo -xy 3000 -geometry 0:0 intro.mp4 -idle;

## display step in the terminal
echo -e "\e[103m\e[30mlightbox-player:\e[90m Playing film...\e[0m" $(date -u)

## mplayer arguments for each screen
PLAYERARGS=(\
    "-udp-master -fs" \
    "-udp-slave  -fs -nosound " \
    "-udp-slave  -fs -nosound " \
    "-udp-slave  -fs -nosound " \
    )

## DEBUG arguments
## "-ss 00:01:50" is the time offset for Sintel demo
if [ $DEBUG = true ] # if single monitor, then enter debug mode for 4 screens
then
    PLAYERARGS=(\
        "-udp-master -screen 0 -osdlevel 3 -ss 00:01:50 -xy $(( MONWIDTH / SCREENS )) -noborder -geometry $(( 0 * MONWIDTH / SCREENS )):$(( ${TOPOFFSETS[3]} * MONWIDTH / SCREENS / PROJWIDTH )) " \
        "-udp-slave  -screen 0 -osdlevel 3 -ss 00:01:50 -xy $(( MONWIDTH / SCREENS )) -noborder -geometry $(( 1 * MONWIDTH / SCREENS )):$(( ${TOPOFFSETS[2]} * MONWIDTH / SCREENS / PROJWIDTH ))  -nosound " \
        "-udp-slave  -screen 0 -osdlevel 3 -ss 00:01:50 -xy $(( MONWIDTH / SCREENS )) -noborder -geometry $(( 2 * MONWIDTH / SCREENS )):$(( ${TOPOFFSETS[1]} * MONWIDTH / SCREENS / PROJWIDTH ))  -nosound " \
        "-udp-slave  -screen 0 -osdlevel 3 -ss 00:01:50 -xy $(( MONWIDTH / SCREENS )) -noborder -geometry $(( 3 * MONWIDTH / SCREENS )):$(( ${TOPOFFSETS[0]} * MONWIDTH / SCREENS / PROJWIDTH ))  -nosound " \
        )
fi

## reset offset if ratio is less than widescreen
if [ $VIDASPECT -lt 2 ]
then
    TOPOFFSETS=(0 0 0 0)
fi

## transmit UDP data required for slave instances to additional ports for them to listen at
## based on https://superuser.com/questions/751184/how-to-sync-two-looping-videos-with-mplayer-and-upd/792635#792635
socat UDP-LISTEN:28760 - | tee >(socat - UDP-DATAGRAM:127.0.0.1:28761) >(socat - UDP-DATAGRAM:127.0.0.1:28762) >(socat - UDP-DATAGRAM:127.0.0.1:28763) >/dev/null &

## run an instance for each screen
## references:
## http://www.mplayerhq.hu/DOCS/man/en/mplayer.1.txt
## for position: https://forum.smplayer.info/viewtopic.php?f=2&t=8726
# -subpos ...
# -fs-border-top  (only used with gl driver, maybe use instead of expand?)
# -monitoraspect $PROJWIDTH:$PROJHEIGHT \
for x in $( seq 0 $(( SCREENS - 1)) ); do
    mplayer.exe -really-quiet \
    -nomouseinput -nojoystick -nolirc \
    -screen $x ${PLAYERARGS[$x]} \
    -udp-ip 127.0.0.1 \
    -udp-port 2876$x \
    -vo direct3d -dr -fixed-vo -framedrop \
    -ao dsound \
    -vf expand=aspect=$PROJWIDTH/$PROJHEIGHT:y="${TOPOFFSETS[$x]}" \
    -utf8 -sub "${SUBTITLES[$x]}" "$FILM" -idle &
done

## terminate all previous parallel command when one ends
## based on https://unix.stackexchange.com/posts/231678/revisions
wait -n
pkill -P $$

## play outro
# mplayer.exe -vo direct3d -fixed-vo -quiet -xy 3000 -geometry 0:0 intro.mp4 -loop 0;

## display step in the terminal
echo -e "\e[103m\e[30mlightbox-player:\e[90m Completed!\e[0m" $(date -u)