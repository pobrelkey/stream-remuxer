

# Stream Remuxer for TVHeadend

A lightweight streaming media proxy which makes configuring [TVHeadend](https://github.com/tvheadend/tvheadend) to serve Internet radio/TV channels easier.

Takes a flat-file list of streaming media channels; serves up MPEG-TS format streams suitable for consumption by TVHeadend, along with an M3U playlist so you can configure your channel list in TVHeadend as an "IPTV Automatic" network.

Works on Linux.  May work on MacOS and other Unixes, with some tweaking.  Won't work on Windows.


### Why?

Nowadays many radio and TV channels stream online.  Those of us who run TVHeadend would love to be able to watch/listen to these channels just by dialing a channel number, as with traditional terrestrial/satellite channels.  Unfortunately, TVHeadend only understands plain-HTTP (not HLS) streams in MPEG2 Transport Stream format, which very few content providers support natively.  What to do?

- You could set up [node-ffmpeg-ts-proxy](https://github.com/Jalle19/node-ffmpeg-mpegts-proxy) to convert the streams, but 1) it uses avconv which isn't available as a package in stock Debian, and 2) it would require me to install NodeJS just to run it.  Sorry, I'd rather install something with a smaller footprint.
- It's possible to set up [custom commands per-channel](https://tvheadend.org/projects/tvheadend/wiki/Custom_MPEG-TS_Input) to stream in content from elsewhere and convert it to an MPEG TS, but configuring this for more than a couple of channels is a massive PITA.
- You know, I did write a [tiny streaming media server in Bash](https://github.com/pobrelkey/alarum) once upon a time... hey, why not use something lightweight like that?  It only has to pipe output from VLC down a TCP connection...

So I wrote this tool, with the following objectives:

- delegates to [VLC](http://www.videolan.org/) - known to understand a wide range of streaming formats
- a shell script - small, comprehensible, tweakable
- simple, flat-file config format
- can optionally transcode streams served up using mutant codecs


### Installation

- Install VLC - `apt-get install vlc`
- Copy `stream-remuxer.sh` and `channels.m3u` to a directory on your local system (for example, `/opt/stream-remuxer`)
- Edit `channels.m3u` to your preferences - see section below on config file format, though an ordinary M3U channel list should suffice
- Configure `stream-remuxer.sh` to be run as an `inetd`-style TCP server.  There are various ways to do this:
  - Assuming your system runs `systemd` (most Linuxes do these days), **TODO**  
  
    - http://0pointer.de/blog/projects/inetd.html
    - https://gist.github.com/drmalex07/28de61c95b8ba7e5017c
  
  - Or, you could install a "proper" `inetd` (like `xinetd`) on your system and configure it to run `stream-remuxer.sh --inetd` whenever it receives a connection on port 9979.  Please see the documentation for your chosen `inetd` for instructions on how to do this.
  - Or, for development purposes, you could simply invoke `stream-remuxer.sh` directly with no arguments - this starts up a server on port 9979, provided you have `busybox` installed, and it has the `nc` applet built in (which is how it's built on any mainstream Linux distro).
- On the machine where you've installed stream-remuxer, browse to http://127.0.0.1:9979/ - assuming everything's working you should see a simple HTML menu:

    **TODO screenshot**

- Now set up an "IPTV Automatic" network in TVHeadend, with the playlist URL as http://127.0.0.1:9979/playlist.m3u - see the [TVHeadend docs](https://tvheadend.org/projects/tvheadend/wiki/Automatic_IPTV_Network) for more details.  You should be able to "scan" this network and have TVHeadend find all the channels in your list.





The above instructions assume you're installing stream-reumxer on the same box as TVHeadend - if you aren't:
- ensure systemd/inetd is configured to listen on an IP address your TVHeadend box can reach, i.e. not 127.0.0.1
- ensure the `BASE_ADDR` variable is correctly set to this address when running stream-remuxer, either at the top of the script or as an environment variable
- change URLs as appropriate in the above instructions to point to the stream-remuxer box and not 127.0.0.1


### Configuration Format

**TODO** explain the format, or just use M3U instead?






Given that there's a real possibility their servers will get hammered by lots of random people testing/tweaking their configuration of this script :trollface:, the stations in the example `channels.m3u` file are ones I don't approve of.  There's no guarantee these stations will still be accessible at the given addresses by the time you read this, so if you try watching one of these streams and nothing happens, don't blame me.  Once you're sure your setup works, replace this file with a list of channels you actually want to watch.





### Caveats

**TODO** 


### License

Distributed under the MIT License. See the [LICENSE](LICENSE) file for more information.
