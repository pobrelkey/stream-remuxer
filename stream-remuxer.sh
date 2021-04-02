#!/usr/bin/env bash

#
# stream-remuxer: remux streaming content for use by TVHeadend
# https://github.com/pobrelkey/stream-remuxer
#
# Copyright (c) 2021 pobrelkey
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#


# Defaults which can be specified via environment variables
# (but which can be overridden by command-line options)
SR_LOCAL_PORT="${SR_LOCAL_PORT:-9979}"
SR_CHANNELS_M3U="${SR_CHANNELS_M3U:-$(dirname "${0}")/channels.m3u}"
SR_LOCAL_ADDR="${SR_LOCAL_ADDR:-127.0.0.1}"


# grok command line options
while getopts 'a:p:c:h' OPT; do
	case "${OPT}" in
		h)
			echo "usage: ${0} [-a local_address] [-p local_port] [-c channels.m3u]"
			exit 0
			;;
		a)
			SR_LOCAL_ADDR="${OPTARG}"
			;;
		p)
			SR_LOCAL_PORT="${OPTARG}"
			;;
		c)
			SR_CHANNELS_M3U="${OPTARG}"
			;;
		\?)
			echo "ERROR: invalid Option: -$OPTARG" 1>&2
			exit 1
			;;
		:)
			echo "ERROR: invalid Option: -$OPTARG requires an argument" 1>&2
			exit 1
			;;
	esac
done

# If manually invoked, spawn a TCP server which will then re-invoke the script
# inetd-style, i.e. with standard input/output piped to the TCP connection.
if [[ -t 1 ]]
then
	echo "Listening on port ${SR_LOCAL_PORT} - channels in ${SR_CHANNELS_M3U}"
	exec busybox nc -ll -w 0 -p "${SR_LOCAL_PORT}" "${SR_LOCAL_ADDR}" -e "${0}" -a "${SR_LOCAL_ADDR}" -p "${SR_LOCAL_PORT}" -c "${SR_CHANNELS_M3U}"
fi

# Check that the channels.m3u file exists
if [[ ! -e "${SR_CHANNELS_M3U}" ]]
then
	echo -ne "HTTP/1.0 500 Internal Server Error\015\012"
	echo -ne "Content-type: text/html\015\012"
	echo -ne "Pragma: no-cache\015\012"
	echo -ne "Connection: close\015\012"
	echo -ne "\015\012"
	echo "<html><head><title>Configuration Error</title></head><body><h1>Configuration Error</h1><p>Must have a <tt>channels.m3u</tt> file</p>${FOOTER}</body></html>"
	exit 1
fi

FOOTER="<hr /><p><a href='/'>Stream Remuxer</a> at ${SR_LOCAL_ADDR} port ${SR_LOCAL_PORT}</p>"

# Read in the channels.m3u content into a Bash associative array
declare -A CHANNEL_EXTINFS
declare -A CHANNEL_URLS
CHANNEL_ID=
CHANNEL_EXTINF=
while true
do
	read LINE
	READSTATUS=$?
	if [[ "${LINE}" =~ ^.?.?.?#EXTM3U ]]
	then
		# skip header line - be sure to catch header lines with UTF-8 BOM
		true
	elif [[ "${LINE}" =~ ^#EXTINF: ]]
	then
		CHANNEL_EXTINF="${LINE}"
	elif [[ "${LINE}" =~ ^[^#] ]]
	then
		if [[ "${CHANNEL_EXTINF}" =~ \ sr-id=\".*\" ]]
		then
			CHANNEL_ID="${CHANNEL_EXTINF#* sr-id=\"}"
			CHANNEL_ID="${CHANNEL_ID%%\"*}"
		fi
		if [[ "x${CHANNEL_ID}" == x && "${CHANNEL_EXTINF}" =~ \ tvg-id=\".*\" ]]
		then
			CHANNEL_ID="${CHANNEL_EXTINF#* tvg-id=\"}"
			CHANNEL_ID="${CHANNEL_ID%%\"*}"
		fi
		if [[ "x${CHANNEL_ID}" == x && "${CHANNEL_EXTINF}" =~ , ]]
		then
			CHANNEL_ID="${CHANNEL_EXTINF##*,}"
		fi
		if [[ "x${CHANNEL_ID}" == x ]]
		then
			# ugly but better than nothing...
			CHANNEL_ID="${LINE}"
		fi
		CHANNEL_ID="${CHANNEL_ID//[^-_a-zA-Z0-9]/_}"
		CHANNEL_EXTINFS["${CHANNEL_ID}"]="${CHANNEL_EXTINF}"
		CHANNEL_URLS["${CHANNEL_ID}"]="${LINE}"
    CHANNEL_ID=
		CHANNEL_EXTINF=
	fi
	if [[ ${READSTATUS} != 0 ]]
	then
		break
	fi
done < "${SR_CHANNELS_M3U}"

# read HTTP headers, ignore all but the URI
read METHOD URI VERSION
HEADER="not blank"
while [[ "x${HEADER}" != 'x' ]]
do
	read -t 0.1 HEADER
done
if [[ "${METHOD}" != 'GET' ]]
then
	echo -ne "HTTP/1.0 501 Unsupported Method\015\012"
	echo -ne "Content-type: text/html\015\012"
	echo -ne "Pragma: no-cache\015\012"
	echo -ne "Connection: close\015\012"
	echo -ne "\015\012"
	echo "<html><head><title>Unsupported method</title></head><body><h1>Unsupported method</h1></body>${FOOTER}</html>"
	exit 0
fi

function notfound() {
	echo -ne 'HTTP/1.0 404 Not Found\015\012'
	echo -ne 'Content-type: text/html\015\012'
	echo -ne 'Pragma: no-cache\015\012'
	echo -ne 'Connection: close\015\012'
	echo -ne '\015\012'
	cat <<-__404__
	<html><head>
	<title>Not Found</title>
	</head><body>
	<h1>404 Not Found</h1>
	${FOOTER}
	</body></html>
__404__
}

case ${URI} in
	/index.m3u*|/playlist.m3u*)
		# serve up an M3U playlist of all channels we know about
		echo -ne 'HTTP/1.0 200 OK\015\012'
		echo -ne 'Content-type: application/mpegurl\015\012'
		echo -ne 'Pragma: no-cache\015\012'
		echo -ne 'Connection: close\015\012'
		echo -ne '\015\012'
		echo '#EXTM3U'
		for CHANNEL_ID in "${!CHANNEL_URLS[@]}"
		do
			echo "${CHANNEL_EXTINFS["${CHANNEL_ID}"]}"
			echo "http://${SR_LOCAL_ADDR}:${SR_LOCAL_PORT}/stream/${CHANNEL_ID}"
		done
		;;

	/|/index.html)
		# serve up a basic HTML menu page
		echo -ne 'HTTP/1.0 200 OK\015\012'
		echo -ne 'Content-type: text/html\015\012'
		echo -ne 'Pragma: no-cache\015\012'
		echo -ne 'Connection: close\015\012'
		echo -ne '\015\012'
		cat <<-__HEADER__
		<html><head>
		<title>stream remuxer (${SR_LOCAL_ADDR}:${SR_LOCAL_PORT})</title>
		</head><body>
		<h1>Stream Remuxer</h1>
		<p><a href='/playlist.m3u'>Playlist</a></p>
		<p>Streams:<ul>
		__HEADER__
		for CHANNEL_ID in "${!CHANNEL_URLS[@]}"
		do
			EXTINF_TAGS="${CHANNEL_EXTINFS["${CHANNEL_ID}"]}"
			if [[ "x${EXTINF_TAGS}" == x ]]
			then
				EXTINF_TAGS="${CHANNEL_ID}"
			fi
			echo "<li><a href='/stream/${CHANNEL_ID}'>${EXTINF_TAGS##*,}</a></li>"
		done
		echo '</ul></p>'
		echo "${FOOTER}"
		echo '</body></html>'
		;;
	
	/stream/*)
		CHANNEL_ID="${URI#/stream/}"
		CHANNEL_ID="${CHANNEL_ID%%\?*}"
		if [[ ! -v CHANNEL_URLS["${CHANNEL_ID}"] ]]
		then
			notfound
			exit 0
		fi
		EXTINF_TAGS="${CHANNEL_EXTINFS["${CHANNEL_ID}"]%%|*}"
		if [[ "x${EXTINF_TAGS}" == x ]]
		then
			EXTINF_TAGS="${CHANNEL_ID}"
		fi
		if [[ ! "${EXTINF_TAGS}" =~ , ]]
		then
			CHANNEL_NAME="${EXTINF_TAGS##*,}"
		else
			CHANNEL_NAME="${EXTINF_TAGS}"
		fi
		if [[ "${EXTINF_TAGS}" =~ \ sr-transcode-opts=\".*\" ]]
		then
			TRANSCODE_OPTS="${EXTINF_TAGS#* sr-transcode-opts=\"}"
			TRANSCODE_OPTS="${TRANSCODE_OPTS%%\"*}:"
		else
			TRANSCODE_OPTS=""
		fi
		if [[ "${EXTINF_TAGS}" =~ \ sr-net-id=\".*\" ]]
		then
			NET_ID="${EXTINF_TAGS#* sr-net-id=\"}"
			NET_ID="${NET_ID%%\"*}:"
		else
			NET_ID=65310
		fi
		if [[ "${EXTINF_TAGS}" =~ \ sr-ts-id=\".*\" ]]
		then
			TS_ID="${EXTINF_TAGS#* sr-ts-id=\"}"
			TS_ID="${TS_ID%%\"*}:"
		elif [[ "x$(which cksum)" != 'x' ]]
		then
			# use cksum to generate an integer TS ID from the channel ID
			TS_ID="$(echo "${CHANNEL_ID}" | cksum)"
			TS_ID="${TS_ID%% *}"
			TS_ID="$((${TS_ID} % 65529))"
		else
			TS_ID=1
		fi
		echo -ne 'HTTP/1.0 200 OK\015\012'
		echo -ne 'Content-type: video/MP2T\015\012'
		echo -ne 'Pragma: no-cache\015\012'
		echo -ne 'Connection: close\015\012'
		echo -ne '\015\012'
		VLC_PID=
		VLC_FIFO="/tmp/stream-remuxer.$$"
		function onexit() {
			if [[ "x${VLC_PID}" != 'x' ]]
			then
				# forcibly kill VLC as otherwise it plays the stream forever
				kill -9 "${VLC_PID}"
			fi
			rm -f "${VLC_FIFO}"
		}
		trap onexit EXIT
		mkfifo -m 0600 "${VLC_FIFO}"
		# start VLC in the background, writing to a FIFO...
		cvlc -I dummy -V vdummy -A adummy --no-dbus \
			--no-random --no-loop --no-repeat \
			--sout-ts-netid="${NET_ID}" --sout-ts-tsid="${TS_ID}" \
			"${CHANNEL_URLS["${CHANNEL_ID}"]}" vlc://quit \
			--sout="#${TRANSCODE_OPTS}file{mux=ts,dst=${VLC_FIFO}}" \
			</dev/null 1>&2 &
		VLC_PID=$!
		# ...then have cat read from that fifo until it can write no more
		# (i.e. the client disconnects)...
		cat "${VLC_FIFO}"
		# ...at which the exit trap kicks in and kills VLC (complicated, but
		# if we just ran VLC dumping to stdout, it wouldn't know when to quit)
		;;
	
	*)
		notfound
		;;

esac
