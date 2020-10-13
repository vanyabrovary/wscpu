#!/usr/bin/env perl
use strict;
use warnings;

use Mojolicious::Lite;
use common::sense;
use Proc::ProcessTable;
use Time::HiRes;

die('Want WSCPU_IP at /etc/enviroment') unless exists $ENV{WSCPU_IP};

app->config( hypnotoad => { listen => ['http://'.$ENV{WSCPU_IP}.':3000'] } );

my $IO = 'Mojo::IOLoop';

get '/' => sub { my $self = shift; $self->render( template => 'ws_page' ); };

helper 'iostat' => sub {
    my $str = '';
my $cpu;
my $i;
my $ic;
my $idle;
my $percent_busy;
my $show_idle;
my $show_usage;
my $total;
my %idle_after;
my %idle_before;
my %total_after;
my %total_before;
my @f;


    open(STAT, "< /proc/stat");

    while(<STAT>) { if (/^cpu(\d+)/) { $cpu = $1; @f = split; $idle_before{$cpu} = $f[4]; $total_before{$cpu} = $f[1] + $f[2] + $f[3] + $f[4] + $f[5] + $f[6] + $f[7] + $f[8] +  $f[9]; }}
    close(STAT);

    Time::HiRes::sleep(0.6);

    open(STAT, "< /proc/stat") or die;

    while(<STAT>) { if (/^cpu(\d+)/) {
    $cpu = $1; @f = split; $idle_after{$cpu} = $f[4];
        $total_after{$cpu} = $f[1] + $f[2] + $f[3] + $f[4] + $f[5] + $f[6] + $f[7] + $f[8] +  $f[9];
    } }

    close(STAT) or die;

    for($i=0; $i <= $cpu; $i++) {
        $total = $total_after{$i} - $total_before{$i};
        $idle  = $idle_after{$i} - $idle_before{$i};
        if ($total == 0) { $percent_busy = 0; } else { $percent_busy = ($total - $idle) * 100 / $total; }
        $show_idle  = 100 - int($percent_busy);
        $show_usage = 101 - $show_idle;
        $ic = $i + 1;
    $str .= "$ic:$show_usage";
        $str .= "," if $ic < 12;
    }
    return $str;
};


helper 'get_w' => sub { 
    my $w = `w`; 
    $w =~ s/\n/<br>/mg; 
    return $w; 
};

helper 'get_process' => sub {
    my $h = {};
    my $str;

    my $t = Proc::ProcessTable->new;

    foreach my $p ( @{ $t->table } ) {
        if ( $p->pctcpu > 0 && $p->cmndline ) {
            $h->{ $p->cmndline } += $p->pctcpu if $p->pctcpu ne 'Inf';
        }
    }
    my $i;

    foreach my $key ( sort { $h->{$b} <=> $h->{$a} } keys %{$h} ) {
        $i++;
        $str .= "<tr><td>$i</td><td>$key</td><td>" . $h->{$key} . "%</td><tr>" if $h->{$key} ne 'Inf';
    }

    return $str;
};

helper 'get_net' => sub {
    my $str = `netstat -ntu | sort -rn | grep -v 127.0.0.1 | grep -v 3000 |grep -v Proto |grep -v Active |sort`;
    $str =~ s/^ {2,}/<tr><td>/mg;
    $str =~ s/\n/<\/td><\/tr>/mg;
    $str =~ s/ {2,}/<\/td><td>/mg;
    $str =~ s/tcp[64]//g;
    return "<table id=net_tbl width=100%>$str</table>";
};

helper 'get_net_ip' => sub {
    my @b = `netstat -ntu | tail -n +3 | awk '{print \$5}' | cut -d: -f1 | sort | uniq -c | sort -nr |perl -lne 's/^\s+//; print $_;' |grep '\.'`;
    my $str;
    foreach (@b) {
    my ($l, $r) = split(" ", $_);
        $str .= "<tr><td>$l</td> <td>$r</td></tr>" if $l and $r;
    }
    return "<br><b>Total ips: " . scalar @b . "</b><br><table id=net_tbl_ip width=100%>$str</table><br>";
};

websocket '/p' => sub {
    my $c  = shift;
    my $ws = $c->tx;
    $IO->stream( $c->tx->connection )->timeout(300);
    $c->on( finish => sub { $c->app->log->debug('Close'); } );
    $IO->recurring( 0.8 => sub { $ws->send( $c->iostat() ); } );
};

websocket '/stream/net' => sub {
    my $self = shift;
    my $ws   = $self->tx;
    $IO->stream( $self->tx->connection )->timeout(15);
    $self->on( finish => sub { my $ws = shift; say 'WS closed.'; } );
    $IO->recurring( 2 => sub { $ws->send( $self->get_net ); } );
};

websocket '/stream/net_ip' => sub {
    my $self = shift;
    my $ws   = $self->tx;
    $IO->stream( $self->tx->connection )->timeout(15);
    $self->on( finish => sub { my $ws = shift; say 'WS closed.'; } );
    $IO->recurring( 2 => sub { $ws->send( $self->get_net_ip ); } );
};

get '/stream/get_process' => sub { 
    my $c = shift; 
    return $c->render( data => '<table>' . $c->get_process . '</table>' ); 
};

websocket '/stream/w' => sub {
    my $c  = shift;
    my $ws = $c->tx;
    $IO->stream( $c->tx->connection )->timeout(15);
    $c->on( finish => sub { my $ws = shift; say 'WS closed.'; } );
    $IO->recurring( 1 => sub { $ws->send( $c->get_w ); } );
};

app->start;

__DATA__


@@nginx_log_page.html.ep

<!DOCTYPE html>
<html>
<%= $content %>
</html>

@@ws_page.html.ep

<!DOCTYPE html>
<html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="#4285f4">
<head>
    <title>awex</title>
    <script type="text/javascript" src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.1/jquery.min.js"></script>

    <style type="text/css">
        body { font-size:10px;}
        ol    { list-style-type:decimal-leading-zero; }
        .num  { float: left; width: 32px;  }
        .prc  { float: left; width: 32px;  }
        .bar  { float: left; width: 320px; }
        .cntc { width: 100%; height: 16px; }
        #net_tbl td {
            background-color: #f1f1c1;
        }
        #net_tbl_ip td {
            background-color: #f1f1c1;
        }

        #mem_tbl td {
            background-color: #f1f1c1;
        }
        #log_tbl td {
            background-color: #f1f1c1;
        }
        td {
            border: 1px solid black;
            border-collapse: collapse;
            vertical-align: top;
        }
    </style>
    <script type="text/javascript">
        $(document).ready(function(){
	    var IP = '<%= $ENV{WSCPU_IP} %>';
            var pnet          = new WebSocket('ws://'+IP+':3000/p');
            pnet.onmessage    = function  (ev)  { html_p('p', ev.data ); };
            pnet.onerror      = function(error) { alert('WebSocket Error: ' + error); };

            var net          = new WebSocket('ws://'+IP+':3000/stream/net');            // netstat    / 2 sec
            net.onmessage    = function  (ev) { html_ev('net', ev.data ); };
            net.onerror      = function(error) { alert('WebSocket Error: ' + error); };

            var net_ip       = new WebSocket('ws://'+IP+':3000/stream/net_ip');            // netstat    / 2 sec
            net_ip.onmessage = function  (ev) { html_ev('net_ip', ev.data ); };
            net_ip.onerror   = function(error) { alert('WebSocket Error: ' + error); };

            var w            = new WebSocket('ws://'+IP+':3000/stream/w');              // tty        / 20 sec
            w.onmessage      = function  (ev) { html_ev('w', ev.data ); };
            w.onerror        = function(error) { alert('WebSocket Error: ' + error); };

        });

        setInterval(function() {
            $.get( 'http://'+IP+':3000/stream/get_process', function( data ) { 
                html_ev('process',data); 
            });
        }, 1000);

	var cpus_cont = 0;

        function html_p(id, data) { 
	    if(data) {

                var arr = data.split(',');

		if(arr.length > 0 && cpus_cont == 0) {
		    cpus_cont = arr.length;

            	    for (var i = 0; i < arr.length; i++) {

                        var key_val = arr[i].split(':');
			if(key_val[0]){
				$('#cpu_container').append("<div id=cpu"+key_val[0]+"></div><br>");
			}
		    }
		}

                for (var i = 0; i < arr.length; i++) {
                    var key_val = arr[i].split(':');
                    $('#cpu'+key_val[0]).html( print_font_color(key_val[0],key_val[1]) );
                }
            }
        }

        function html_ev(id, data) { if(data){$('#'+id).html( data );} }

        function print_font_color(num,count){  return '<div class="num">' + num + '</div><div class="prc"><b' + get_font_color(count) + '>' + ( count - 1 ) + '%</b></div><div class="bar">['+print_dot(count)+']</div>';  }

        function print_dot(count){
            var dot = '';
            for (var d = 0; d < count; d++)       { dot = dot + '<b' + get_font_color(d) + '>|</b>'; }
            for (var d = 0; d < 100 - count; d++) { dot = dot + '<b' + get_font_color(0) + '>|</b>'; }
            return dot;
        }

        function get_font_color(count){
            var font_color = '';
            if( count <  1  )               { font_color =  '#F2F2F2;'; }
            if( count >= 1  && count < 60 ) { font_color =  'green';    }
            if( count >= 60 && count < 80 ) { font_color =  'yellow';   }
            if( count >= 80 )               { font_color =  'red';      }
            return ' style="color:' + font_color + ';" ';
        }
    </script>
</head>
<body class='default'>


<table id="cpu_tbl" width="100%">
    <tr>
    <td width="70%" id='cpu_container'>
    </td>
    <td width="30%">
        <h3>Load average</h3><div id="w"></div>
    </td>
    </tr>
</table>
<br>
<table width="100%">
<tr>
<td width="33%">
    <h3>Netstat IPs</h3>
    <div id="net_ip"></div>
</td>
<td width="33%">
    <h3>Netstat</h3>
    <div id="net"></div>
</td>
</tr>
</table>
<br>
<table width="100%">
<tr>
<td width="100%">
    <h3>Process</h3>
    <div id="process"></div>
</td>
</tr>
</table>

</body>
</html>
