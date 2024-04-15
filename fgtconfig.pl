#! /usr/bin/perl -w
use strict ;
use warnings ;
use Getopt::Long ;

use cfg_fgtconfig ;
use cfg_configstats ;

use vars qw ($debug $config $routing $ipsec $splitconfig $color $html $stats $fullstats $ruledebug $nouuid $serve $help) ;
use lib "." ;

GetOptions(
   "debug=s"       => \$debug,
   "ruledebug=s"   => \$ruledebug,
   "config=s"      => \$config,
   "routing"       => \$routing,
   "splitconfig=s" => \$splitconfig,
   "ipsec"         => \$ipsec,
   "color"         => \$color,
   "html"          => \$html,
   "stats"         => \$stats,
   "fullstats"     => \$fullstats,
   "nouuid"        => \$nouuid,
   "serve"         => \$serve,
   "help"          => \$help
) ;


# Init
$help 	    = 0 if (not(defined($help))) ;
$debug      = 0 if (not(defined($debug))) ;
$stats      = defined($stats)     ? 1 : 0 ;
$fullstats  = defined($fullstats) ? 1 : 0 ;
$routing    = defined($routing)   ? 1 : 0 ;
$ipsec      = defined($ipsec)     ? 1 : 0 ;
$nouuid     = defined($nouuid)      ? 1 : 0 ;
$serve      = defined($serve)      ? 1 : 0 ;

if ($help) {
   print_help();
   exit ; 
   }

# Start serving the web interface if specified
if ($serve) {
   use Mojolicious::Lite -signatures;
   use File::Temp 'tempfile';

   get '/' => sub ($c) {
      $c->render(template => 'index');
      };

   post '/upload' => sub {
      my $c = shift;

      my $file = $c->req->upload('file');
      my $filename = $file->filename;

      # make sure file is saved as local
      my $asset = $file->asset;
      my $temp_path;
      if ($asset->isa('Mojo::Asset::Memory')) {
         my ($fh, $filename) = tempfile();
         $asset->move_to($filename);
         $temp_path = $filename;
      } else {
         $temp_path = $asset->path;
      }

      # apply configuration
      my $fgtconfig = cfg_fgtconfig->new(configfile => $temp_path, debug_level => $debug) ;

      $fgtconfig->dis->stats_flag('1')   if $stats ;
      $fgtconfig->dis->routing_flag('1') if $routing ;
      $fgtconfig->dis->ipsec_flag('1')   if $ipsec ;
      $fgtconfig->dis->color_flag('1')   if $color ;
      $fgtconfig->debug($debug)  if (defined($debug)) ;
      $fgtconfig->ruledebug($ruledebug) if (defined($ruledebug)) ;

      # parse
      $fgtconfig->parse() ;
      $fgtconfig->analyse() ;

      # get ouput
      my $captured_output = capture_output(sub { $fgtconfig->dis->display() });

      # apply span patches from htmlizer
      my @lines = split /\n/, $captured_output;

      for my $line (@lines) {         
         color_features(\$line) ;
         color_warnings(\$line) ;
         color_vdom(\$line) ;
      }

      my $modified_text = join "\n", @lines;

      $c->render(template => 'upload', msg => $modified_text, filename => $filename);
      };

   # start mojo
   app->start('daemon', '-l', 'http://*:8080');
   }

# Sanity
die "-config is required" if (not(defined($config))) ;

# If fullstat is asked, only do some statisctics counting per vdom

if ($fullstats) {

   my $cst = configstats->new(configfile => $config, debug_level => $debug) ;
   $cst->start() ;
   exit;
   }
 
my $fgtconfig = cfg_fgtconfig->new(configfile => $config, debug_level => $debug) ;

# Set display flags
$fgtconfig->dis->stats_flag('1')   if $stats ;
$fgtconfig->dis->routing_flag('1') if $routing ;
$fgtconfig->dis->ipsec_flag('1')   if $ipsec ;
$fgtconfig->dis->color_flag('1')   if $color ;
$fgtconfig->debug($debug)  if (defined($debug)) ;
$fgtconfig->ruledebug($ruledebug) if (defined($ruledebug)) ;

# load the config and start analysis
$fgtconfig->parse() ;
$fgtconfig->analyse() ;

#$fgtconfig->dump() ;
if (defined($splitconfig)) {

   # Default to current dir if not directory specified
   $splitconfig = "." if $splitconfig eq "" ;

   $fgtconfig->splitconfigdir($splitconfig) ;

   # Pre-split processing
   $fgtconfig->pre_split_processing(nouuid => $nouuid) ;

   # Creates one file per vdom and FGTconfig file
   $fgtconfig->splitconfig($config) ;
   }
else {
   $fgtconfig->color(1) if (defined($color)) ;
   $fgtconfig->dis->display() ;
   }

# ---

sub print_help {

print "\nusage: fgtconfig.pl -config <filename> [ Operation selection options ]\n";

print <<EOT;

Description: FortiGate configuration file summary, analysis, statistics and vdom-splitting tool

Input: FortiGate configuration file

Selection options:

[ Operation selection ]

   -fullstats                                                   : create report for each vdom objects for build comparison

   -splitconfig                                                 : split config in multiple vdom config archive with summary file
   -nouuid                                                      : split config option to remove all uuid keys (suggest. no)


Display options:
    -routing                                                    : display routing information section if relevant (suggest. yes)
    -ipsec                                                      : display ipsec information sections if relevant (suggest. yes)
    -stat                                                       : display some statistics (suggest. yes)
    -color                                                      : ascii colors
    -html                                                       : HTML output
    -serve                                                      : start serving a mojo http server
    -debug                                                      : debug mode
    -ruledebug                                                  : rule parsing debug

EOT
   }

sub capture_output {
    my $function = shift;
    {
        local *STDOUT;
        open STDOUT, '>', \my $buffer or die "Can't open STDOUT: $!";

        $function->(@_);

        return $buffer;
    }
}

sub color_features {

   my $aref_line = shift ;

   # 'no' in green
   $$aref_line =~ s/=no/=<span style=\"color:green\">no<\/span>/g; 

   # 'YES' in bold red
   $$aref_line =~ s/=YES/=<span style=\"color:red;font-weight: bold;\">YES<\/span>/g;  

   }

# ---

sub color_warnings {

   my $aref_line = shift ;

   my $color_flag = 0 ;

   ($$aref_line =~ s/warn:([^\|]*)/warn:<span style=\"color:#f2c600;font-weight: bold;\">$1<\/span>/ ) ;

   }

# ---

sub color_vdom {

   my $aref_line = shift ;

   if ($$aref_line =~ /^\|\svdom:\s\[\s/) {
      # This is a root vdom (with [ ]), color in red
            
      $$aref_line =~ s/vdom: \[ (\S*) \]/vdom: <span style=\"color:red;font-weight: bold;">\[ $1 \]<\/span>/
      }
     else {
      $$aref_line =~ s/vdom: (\S*)/vdom: <span style=\"color:red;font-weight: bold;">$1<\/span>/ ;
      }

   }


__DATA__
@@ index.html.ep
% layout 'default';
% title 'fgtconfig';
<h1>fgtconfig</h1>
<form action="/upload" method="post" enctype="multipart/form-data">
   <input type="file" name="file">
   <button type="submit">Upload</button>
</form>

@@ upload.html.ep
% layout 'default';
% title 'fgtconfig - result';
<h1><%= $filename %></h1>
<div class="output"><%== $msg %></div>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head>
   <title><%= title %></title>
   <link rel="stylesheet" href="https://components.konst.fish/main.css">
   <style>
      div {
         font-family:'Lucida Console', monospace;
         white-space: pre-wrap;
      }

      span {
         font-family:'Lucida Console', monospace;
         white-space: pre-wrap;
      }
   </style>
  </head>
  <body><%= content %></body>
</html>