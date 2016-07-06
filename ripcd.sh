#!/bin/bash

# Default is to write out both mp3 and flac:
OUTPUTTYPE="mp3,flac"

usage () {
cat <<EOF
USAGE: $0 -od OUTPUTDIR [ -ot OUTPUTTYPE ]

where:

 - OUTPUTDIR is the top directory where the artist directory will be stored, and the tracks within it.

 - OUTPUTTYPE specifies the comma-separated list of formats to use. Defaults: \"$OUTPUTTYPE\"

EOF
  
}

OUTPUTDIR=""

while [ $# -gt 0 ]
do
  if [ "$1" = "-od" ]
  then
    OUTPUTDIR="$2"
    shift
  elif [ "$1" = "-ot" ]
  then
    OUTPUTTYPE="$2"
    shift
  elif [ "$1" = "-h" ]
  then
    usage
    exit 0
  else
    echo "ERROR: Unrecognized option $1"
    exit 1
  fi
  shift
done


if [ "$OUTPUTDIR" = "" ]
then
  echo "ERROR: OUTPUTDIR was not specified"
  exit 1
fi

if [ "$OUTPUTTYPE" = "" ]
then
  echo "ERROR: OUTPUTTYPE was not specified"
  exit 1
fi

echo "Note: OUTPUTDIR:  $OUTPUTDIR"
echo "Note: OUTPUTTYPE: $OUTPUTTYPE"

mkdir -p $OUTPUTDIR

required_packages=()
for package in abcde lame eyed3 glyrc imagemagick flac
do
  version=$(dpkg --status $package 2>&1 | grep -i Version:)
  if [ -n "$version" ]
  then
    echo "Note: package $package is installed: version == $version"
  else
    echo "Note: package $package is not installed. Queuing for installation"
    required_packages+=($package)
  fi
done

if [ -n "${required_packages[*]}" ]
then
  echo "Note: Installing ${required_packages[@]}"
  sudo apt-get -y install ${required_packages[@]}
fi

tmp_config_file=/tmp/abcde.conf.$$
tmp_abcde=/tmp/abcde.tmp.$$
tmp_log=/tmp/ripcd.sh.log.$$

trap "rm -f $tmp_config_file $tmp_abcde $tmp_log" EXIT HUP INT QUIT

#
# The following file was taken from the sample configuration file at
# http://andrews-corner.org/abcde.html on Tue Jul 5 17:48:11 PDT 2016
#
cat > $tmp_config_file <<'EOF'
# -----------------$HOME/.abcde.conf----------------- #
#
# A sample configuration file to convert music cds to all of these:
#       - MP3 format using abcde version 2.7.1
#       - FLAC using abcde version 2.7.2
#
#       http://andrews-corner.org/abcde.html
# -------------------------------------------------- #
# Encode tracks immediately after reading. Saves disk space, gives
# better reading of 'scratchy' disks and better troubleshooting of
# encoding process but slows the operation of abcde quite a bit:
LOWDISK=y
# Specify the method to use to retrieve the track information,
# the alternative is to specify 'cddb':
### CDDBMETHOD=musicbrainz # <-- this did not respond as of Tue Jul  5 19:06:02 PDT 2016 so switch to cddb
CDDBMETHOD=cddb
# Make a local cache of cddb entries and then volunteer to use
# these entries when and if they match the cd:
CDDBCOPYLOCAL="y"
CDDBLOCALDIR="$HOME/.cddb"
CDDBLOCALRECURSIVE="y"
CDDBUSELOCAL="y"
# Specify the encoder to use for MP3. In this case
# the alternatives are gogo, bladeenc, l3enc, xingmp3enc, mp3enc.
MP3ENCODERSYNTAX=lame
# Specify the encoder to use for FLAC. In this case
# flac is the only choice.
FLACENCODERSYNTAX=flac
# Specify the path to the selected encoder. In most cases the encoder
# should be in your $PATH as I illustrate below, otherwise you will
# need to specify the full path. For example: /usr/bin/flac
FLAC=flac
LAME=lame
# Specify your required encoding options here. Multiple options can
# be selected as '--preset standard --another-option' etc.
# The '-V 2' option gives VBR encoding between 170-210 kbits/s.
LAMEOPTS='-V 0'
# Specify your required encoding options here. Multiple options can
# be selected as '--best --another-option' etc.
# Overall bitrate is about 880 kbs/s with level 8.
FLACOPTS='-s -e -V -8'
# Output types to include FLAC and MP3 (comma-separated list) :
OUTPUTTYPE="<<OUTPUTTYPE>>"
# The cd ripping program to use. There are a few choices here: cdda2wav,
# dagrab, cddafs (Mac OS X only) and flac. New to abcde 2.7 is 'libcdio'.
CDROMREADERSYNTAX=cdparanoia
# Give the location of the ripping program and pass any extra options,
# if using libcdio set 'CD_PARANOIA=cd-paranoia'.
CDPARANOIA=cdparanoia
CDPARANOIAOPTS="--never-skip=40"
# Give the location of the CD identification program:
CDDISCID=cd-discid
# Give the base location here for the encoded music files.
OUTPUTDIR="<<OUTPUTDIR>>"
# The default actions that abcde will take.
ACTIONS=cddb,playlist,read,encode,tag,move,clean
# Decide here how you want the tracks labelled for a standard 'single-artist',
# multi-track encode and also for a multi-track, 'various-artist' encode:
OUTPUTFORMAT='${ARTISTFILE}/${ALBUMFILE}/ripped-from-cd-${OUTPUT}/${TRACKNUM}.${TRACKFILE}'
VAOUTPUTFORMAT='Various/${ALBUMFILE}/ripped-from-cd-${OUTPUT}/${TRACKNUM}.${ARTISTFILE}-${TRACKFILE}'
# Decide here how you want the tracks labelled for a standard 'single-artist',
# single-track encode and also for a single-track 'various-artist' encode.
# (Create a single-track encode with 'abcde -1' from the commandline.)
ONETRACKOUTPUTFORMAT='${ARTISTFILE}/${ALBUMFILE}/ripped-from-cd-${OUTPUT}/${ALBUMFILE}'
VAONETRACKOUTPUTFORMAT='Various-${ALBUMFILE}/ripped-from-cd-${OUTPUT}/${ALBUMFILE}'
# Create playlists for single and various-artist encodes. I would suggest
# commenting these out for single-track encoding.
PLAYLISTFORMAT='${ARTISTFILE}/${ALBUMFILE}/ripped-from-cd-${OUTPUT}/${ALBUMFILE}.m3u'
# This function takes out dots preceding the album name, and removes a grab
# bag of illegal characters. It allows spaces, if you do not wish spaces add
# in -e 's/ /_/g' after the first sed command.
mungefilename ()
{
  echo "$@" | sed -e 's/^\.*//' | tr -d ":><|*/\"'?[:cntrl:]"
}
# What extra options?
MAXPROCS=2                              # Run a few encoders simultaneously
PADTRACKS=y                             # Makes tracks 01 02 not 1 2
EXTRAVERBOSE=2                          # Useful for debugging
COMMENT='abcde version 2.7.2'           # Place a comment...
EJECTCD=y                               # Please eject cd when finished :-)
EOF

# From the page at http://andrews-corner.org/abcde.html we read:
#
#    The most obvious area to change is the MP3 encoding options but you
#    will find that the example above will deliver perfectly acceptable
#    sound on most systems. For those who want the maximum possible bitrate
#    you could always try a slightly crazy -V 0 which gives between 220-260
#    kbits/s or better still read the Hydrogen Audio page on lame options
#    and go from there. Tagging is done post-encoding so options can be
#    added to EYED3OPTS in this abcde.conf file if you wish.
#

sed -i \
    -e "s%<<OUTPUTDIR>>%$OUTPUTDIR%g" \
    -e "s%<<OUTPUTTYPE>>%$OUTPUTTYPE%g" \
    $tmp_config_file

cat $tmp_config_file

# Hack around a bug where the comment does not show up in Rhythmbox:
#
#    The "eng:c0:" part was reverse engineered from editing the comment
#    field in Rhythmbox and then running eyeD3 on the resulting .mp3 file:
#
orig_abcde=$(which abcde)
echo "Note: Hacking $orig_abcde into $tmp_abcde to allow Rhythmbox to see the comment tags"
cat $orig_abcde | sed 's%COMMENTOUTPUT:+--comment=::%COMMENTOUTPUT:+--comment=eng:c0:%g' > $tmp_abcde
chmod a+x $tmp_abcde
diff -u $orig_abcde $tmp_abcde

time $tmp_abcde -c $tmp_config_file | tee $tmp_log

# Copy the script and the log into the directories being produced. Scrape the directories from the log:
sed -n '/^movetrack/s%^.*track[0-9]*\.[a-zA-Z0-9]* %%gp' < $tmp_log | sed 's,^\(.*\)/\([^/]*\)$,\1,g' | sort | uniq | while read destination_dir
do
  rip_log=$destination_dir/rip.log
  echo "Note: Writing rip log into $rip_log"
  (
    echo "Date: $(date)"
    echo "Note: Script used to rip the files in this directory is $0 and contains"
    echo "---- cut here ----"
    cat $0
    echo "---- cut here ----"
    echo
    echo "Rip log:"
    echo
    cat $tmp_log
  ) > "$rip_log"
done
