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


# User-tweakable parameters...
LISTEN_PORT="${LISTEN_PORT:-9979}"
CHANNELS_M3U="${CHANNELS_M3U:-$(dirname "${0}")/channels.m3u}"
BASE_ADDR="${BASE_ADDR:-127.0.0.1}"


########################################################################
# (no user-serviceable parts below this line)


# Check that the channels.m3u file exists
if [[ ! -e "${CHANNELS_M3U}" ]]
then
	echo "ERROR: must have a channels.m3u file" 1>&2 
	exit 1
fi

# If manually invoked, spawn a TCP server which will then re-invoke the script
# inetd-style, i.e. with standard input/output piped to the TCP connection.
if [[ "${1}" != '--inetd' ]]
then
	echo "Listening on port ${LISTEN_PORT} - channels in ${CHANNELS_M3U}"
	exec busybox nc -ll -w 0 -p "${LISTEN_PORT}" -e "${0}" --inetd
fi

# Read in the channels.txt content into a Bash associative array
declare -A CHANNEL_EXTINFS
declare -A CHANNEL_URLS
CHANNEL_EXTINF=
while read LINE
do
	if [[ "${LINE}" =~ ^#EXTINF: ]]
	then
		CHANNEL_EXTINF="${LINE}"
	elif [[ "${LINE}" =~ ^[^#] ]]
	then
		if [[ "${CHANNEL_EXTINF}" =~ \ sr-id=\".*\" ]]
		then
			CHANNEL_ID="${CHANNEL_EXTINF#* sr-id=\"}"
			CHANNEL_ID="${CHANNEL_ID%%\"*}"
		elif [[ "${CHANNEL_EXTINF}" =~ \ tvg-id=\".*\" ]]
		then
			CHANNEL_ID="${CHANNEL_EXTINF#* tvg-id=\"}"
			CHANNEL_ID="${CHANNEL_ID%%\"*}"
		elif [[ "${CHANNEL_EXTINF}" =~ , ]]
		then
			CHANNEL_ID="${CHANNEL_EXTINF##*,}"
		else
			# ugly but better than nothing...
			CHANNEL_ID="${LINE}"
		fi
		CHANNEL_ID="${CHANNEL_ID//[^-_a-zA-Z0-9]/_}"
		CHANNEL_EXTINFS["${CHANNEL_ID}"]="${CHANNEL_EXTINF}"
		CHANNEL_URLS["${CHANNEL_ID}"]="${LINE}"
		CHANNEL_EXTINF=
	fi
done < "${CHANNELS_M3U}"

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
	echo "<html><head><title>Unsupported method</title></head><body><h1>Unsupported method</h1></body></html>"
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
	<title>stream remuxer (${BASE_ADDR}:${LISTEN_PORT})</title>
	</head><body>
	<h1>404 Not Found</h1>
	<hr /><p><a href='/'>Stream Remuxer</a> at ${BASE_ADDR} port ${LISTEN_PORT}</p>
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
			echo "http://${BASE_ADDR}:${LISTEN_PORT}/stream/${CHANNEL_ID}"
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
		<title>stream remuxer (${BASE_ADDR}:${LISTEN_PORT})</title>
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
		echo "<hr /><p><a href='/'>Stream Remuxer</a> at ${BASE_ADDR} port ${LISTEN_PORT}</p>"
		echo '</body></html>'
		;;
	
	/stream/*)
		URI2="${URI#/stream/}"
		CHANNEL_ID="${URI2%%\?*}"
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
		echo -ne 'HTTP/1.0 200 OK\015\012'
		echo -ne 'Content-type: video/MP2T\015\012'

		echo -ne 'Pragma: no-cache\015\012'
		echo -ne 'Connection: close\015\012'
		echo -ne '\015\012'
		NONCE="__stream-remuxer_$$__"
		(
			cvlc -I dummy -V vdummy -A adummy --no-dbus \
				--no-random --no-loop --no-repeat \
				--telnet-password "${NONCE}" \
				"${CHANNEL_URLS["${CHANNEL_ID}"]}" \
				--sout="#${TRANSCODE_OPTS}file{mux=ts,dst=/dev/fd/3}" \
				</dev/null 1>&2
		) 3>&1 | (
			# copy output from VLC until we can write no more (i.e. client disconnects)...
			cat 2>/dev/null
			# ...then forcibly kill VLC as otherwise it'll stream forever
			VLC_PID="$(ps auwwx | awk "(/-I dummy -V dummy -A dummy/ && /${NONCE}/ && !/awk/){print \$2}")"
			if [[ "x${VLC_PID}" != x ]]
			then
				kill -9 ${VLC_PID}
			fi
		)
		;;
	
	*)
		notfound
		;;

esac
