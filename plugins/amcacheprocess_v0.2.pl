#!/usr/bin/perl 

#use warnings;
use File::Find;
use File::Copy;
use File::Basename;
use Digest::MD5 qw(md5_hex);
use Cwd 'abs_path';
use Cwd;
use Switch;
use Getopt::Long;
use Config::Tiny;
use File::Path;
use Encode;
use Pod::Usage;
use DateTime;
use File::Path::Tiny;
use DBD::SQLite;

$version = 0.02;

#Get the date
my $dt = DateTime->now;
my $ymd = $dt->ymd;

#amcachekeys
# Used to grab only valid lines from regripper output
#|AmCache_InventoryApplication|
#|AmCache|
#|AmCache_CreationTime|
#|AmCache_PECompileTime|
#grep "#km" amcache_2020-03-10_Step_5.filecheck_distil_nomatch_trim.txt | cut -f1 -d\# | sed 's/^[ \t]*//;s/[ \t]*$//' | cut -f2 -d\| |  sed 's/\"//g' > pulllist
#fgrep -f  pulllist_20200310 amcache_2020-03-10.txt | cut -d\| -f 8,10 | cut -f1-2 -d\_ | sed 's/20200309\/Amcache_//' | awk 'FS="|" { print $2 "|" $1 }'

#=============================================================================================
# Addslash
#=============================================================================================
sub addslash {
    my ($path) = @_;

    my $lastchar =  substr($path,length($path)-1,1);
    if ($lastchar ne "/") {
        $path .= "/";
    }
    return($path);
}
#=============================================================================================

#=============================================================================================
# checksqlite
#=============================================================================================
sub chkdbsql {
    my ($database) = @_;
    my $dberror = 0;
    
    #die "Database file does not exist" unless -f "as2con.db";
    my $driver   = "SQLite"; 
    my $dsn = "DBI:$driver:dbname=$database";
    my $userid = "";
    my $password = "";
    #print "$dsn\n";
    #my $dbase = DBI->connect($dsn, "", "", {RaiseError => 1}) or die $DBI::errstr;
    my $dbh = DBI->connect($dsn, $userid, $password, { PrintError => 0, RaiseError => 0 });
    my $stmt = qq(SELECT * from review;);
    my $sth = $dbh->prepare( $stmt );
    #my $rv = $sth->execute(); # or die $DBI::errstr;
    if ($DBI::errstr) {
       print "DB: Error\n";
       $dberror = 0;
      } else {
       print "DB: Good\n";
       $dberror++;
    }
    $dbh->disconnect;
    return $dberror; 
}
#=============================================================================================

#=============================================================================================
# getreviewdb
#=============================================================================================
sub getreviewdb {
     #my () = @_;
     
     #Now run freq analysis through os_distill filecheck
     #print "$ir_file_distil -i $outfilesha -o $outfiledistilnsrl $ir_file_distil_opt $ir_file_distil_filecheck $ir_file_distil_reviewlist\n";
     print "Gathering reviewlist databases (Looking for .db)...\n";
     opendir(DIR, ".");
     my @reviewlistfiles = grep(/\.db$/,readdir(DIR));
     closedir(DIR);
     foreach $rlf (@reviewlistfiles) {
        print "\t$rlf\n";
     }
     
     my $rvlistopt = "";
     if (($#reviewlistfiles+1) <= 0) {
         print "\tNone found.\n";
       } else {
         print "Checking reviewlist sqlite databases...\n";
         my $dircwd = getcwd();
         
         foreach $rlf (@reviewlistfiles) {
            my $dberror = chkdbsql(addslash($dircwd). $rlf);
            if ($dberror >= 1) {
               $rblistopt .= " " . $ir_file_distil_reviewlist . " " .addslash($dircwd). $rlf;
               print "$rblistopt\n";
            }
         }
     }
     print "\n";
     return($rblistopt);
}
#=============================================================================================


#Step0
sub regrip_sha {
     my ($step,$outfilereg,$mntdrive,$regrip,$regrip_amcache_plugin,$outfile) = @_;

     #print "find $mntdrive -print -exec $regrip  -r {}  -p $regrip_amcache_plugin \\; > amcache_$ymd.txt \n";
     open(FNDOUT, '>', $outfilereg) or die "Could not open file '$outfilereg' $!";
     open(FND, "find $mntdrive -print -exec $regrip  -r {}  -p $regrip_amcache_plugin \\\; |");
     #open(FND, "find $mntdrive -print -exec $wbamcache {} \\\; |");
     while ( defined( my $line = <FND> )  ) {
         chomp($line);
         print "$line\n" if $opt_v;
         print FNDOUT "$line\n";
     }
     close(FND);
     close(FNDOUT);
     print "\n\nCompleted with RegRipper.\n";
}

sub gethash {
     my ($step,$outfilereg,$outfilesha ) = @_;
    
     print "Extracting SHA1 hashes from $outfilereg\n";
     #cut -f8 -d\| amcache{datetime}.txt | sort | uniq | grep -v amcache | sed '/^[[:space:]]*$/d' |  grep -v -i "plugins" > amcache{datetime}.sha
     #Step 0
     
     open(FNDOUT, '>', $outfilesha) or die "Could not open file '$outfilesha' $!";
     open(SHA, "grep -a '\|AmCache_' $outfilereg | grep -v 'Hive:' | cut -f9 -d\\| | sort | uniq | grep -v amcache | sed '/^[[:space:]]*\$/d' |  grep -v -i 'plugins' |");
     while ( defined( my $line = <SHA> )  ) {
         chomp($line);
         print "$line\n" if $opt_v;
         print FNDOUT "$line\n";
     }
     close(SHA);
     close(FNDOUT);     
     print "\nCompleted with SHA1 extraction.\n"; 
     #return($outfilesha);
}

#Step1
sub run_nsrl {
     my ($step,$outfilesha,$outfile,$outfiledistilnsrl,$ir_file_distil,$ir_file_distil_nsrl,$ir_file_distil_reviewlist,$ir_file_distil_op) = @_; 
     
     print "Running $outfilesha hashes against NSRL.\n";

     print "$ir_file_distil  $ir_file_distil_nsrl $ir_file_distil_reviewlist $ir_file_distil_opt --infile $outfilesha --out $outfiledistilnsrl $rblistopt\n"; 
     
     open(DISTIL, "$ir_file_distil  $ir_file_distil_nsrl   $ir_file_distil_opt --infile $outfilesha --out $outfiledistilnsrl $rblistopt |");
     while ( defined( my $line = <DISTIL> )  ) {
         chomp($line);
         print "$line\n" if $opt_v;
         #print FNDOUT "$line\n";
     }
     close(DISTIL);
}

#Step2
sub gen_nsrl_categories {
     my ($step,$outfiledistilnsrl,$nsrlappoutfile) = @_;

     #Pull out the application types from NSRL output
     my $nsrlapptypecmd = "cut -f6 -d\\| ".$outfiledistilnsrl."_match.csv | sort | uniq -c";
     #print $nsrlapptypecmd."\n" if $verbose;
     open(NSRLAppOut, '>', $nsrlappoutfile) or die "Could not open file '$nsrlappoutfile' $!";
     open(NSRLAppType, "$nsrlapptypecmd |");
     while ( defined( my $line = <NSRLAppType> )  ) {
         chomp($line);
         print "$line\n" if $opt_v;
         print NSRLAppOut "$line\n";
     }
     close(NSRLAppType);    
     close(NSRLAppOut); 
##     print "\n\nCompleted IR_Distil NSRL & Reviewlist/Whitelist review. Review file ".$outfiledistilnsrl."_nomatch.txt\n";      
     print "** NOTE: Review file ".$nsrlappoutfile." for application categories that are not allowed on the machines.\n";
}

#Step3
sub pull_sha1 {
     my ($step,$nsrlsha1,$outfiledistilnsrl) = @_;
     
     #Pull hashes from match
     #cut -f1 -d\| $outfiledistilnsrl | sed 's/\"//g' | grep -v SHA1 > nsrl_hashes
     my $nsrlapptypecmd = "cut -f1 -d\\| ".$outfiledistilnsrl."_match.csv | sed 's/\"//g' | grep -v SHA1";
     print "$nsrlapptypecmd\n" if $verbose;
     open(NSRLAppOut, '>', $nsrlsha1) or die "Could not open file '$nsrlsha1' $!";
     open(NSRLAppType, "$nsrlapptypecmd |");
     while ( defined( my $line = <NSRLAppType> )  ) {
         chomp($line);
         print "$line\n" if $opt_v;
         print NSRLAppOut "$line\n";
     }
     close(NSRLAppType);    
     close(NSRLAppOut);    
     print "\nPulled SHA1 hashes from matched NSRL/Reviewlist/Whitelist matches and saved to ".$nsrlsha1."\n";

}

#Step4
sub freq_analysis {
     my ($step,$nomatchlines,$outfilereg,$nsrlsha1) = @_;
     
     #Pull lines that do not match 
     #grep -a AmCache_ amcache_2019-05-08.txt | grep -v Hive: | grep -v -f nsrl_hashes > z
     #Run filenames through filecheck (Freq Analysis step)
     #cut -f7 -d\| z | sort | uniq -c | sed -e 's/^[ \t]*//' | sort -t" " -k2 > z1
     my $nsrlapptypecmd = "grep -a AmCache_ ".$outfilereg." | grep -v Hive: | grep -v -f ".$nsrlsha1." | cut -f8 -d\\| | sort | uniq -c | sed -e 's/^[ \t]*//' | sort -t' ' -k2";
     print "$nsrlapptypecmd\n" if $verbose;
     open(freqanalysisout, '>', $nomatchlines) or die "Could not open file '$nomatchlines' $!";
     open(NSRLAppType, "$nsrlapptypecmd |");
     while ( defined( my $line = <NSRLAppType> )  ) {
         chomp($line);
         print "$line\n" if $opt_v;
         print freqanalysisout "$line\n";
     }
     close(NSRLAppType);    
     close(freqanalysisout);    
     print "Extracted fullpath and filenames from NSRL step no matches. Created frequncy analysis file called: ".$nomatchlines."\n";
}


#Step5
sub distill {
     my ($step,$ir_file_distil,$nomatchlines,$outfiledistilfilecheck,$ir_file_distil_opt,$ir_file_distil_filecheck,$rblistopt) = @_;
     
     print "File Distilling...\n";     
     #open(DISTIL, "$ir_file_distil --infile $nomatchlines --out $outfiledistilfilecheck $ir_file_distil_opt $ir_file_distil_filecheck $ir_file_distil_reviewlist |");
     print "$ir_file_distil --infile $nomatchlines --out $outfiledistilfilecheck $ir_file_distil_opt $ir_file_distil_filecheck $rblistopt\n";
     open(DISTIL, "$ir_file_distil --infile $nomatchlines --out $outfiledistilfilecheck $ir_file_distil_opt $ir_file_distil_filecheck $rblistopt |");
     while ( defined( my $line = <DISTIL> )  ) {
         chomp($line);
         print "$line\n" if $opt_v;
         #print FNDOUT "$line\n";
     }
     close(DISTIL); 
}

sub dupes {
    my ($step,$outfilereg,$dupesout0,$dupesout1,$dupesoutreview) = @_;

    $amkeys = '-e \|AmCache_InventoryApplication\| -e \|AmCache\| -e \|AmCache_CreationTime\| -e \|AmCache_PECompileTime\| ';
    #$cmd0 = 'fgrep -f ./amkeys  ./test.txt  | cut -f8-9 -d\|   | awk \' FS="|" { print $2 "|" $1 } \' ';
    my $cmd0 = 'fgrep '.$amkeys.' '.$outfilereg.' | cut -f8-9 -d\|   | awk \' FS="|" { print $2 "|" $1 } \' '; 
    $cmd0 .= ' | cut -f1 -d\| | uniq -c   | sed \'s/^[ \t]*//;s/[ \t]*$//\' | sort | awk \'$1 > 1 { print $2 }\' ';
    #print "$cmd0\n";
    open(DupesOut0, '>', $dupesout0) or die "Could not open file '$dupesout0' $!";
    open(FND, "$cmd0 |" )  or die "Error with execution: $!";
    while ( defined( my $line = <FND> )  ) {
         chomp($line);
         print DupesOut0 "$line\n";
    }
    close(FND);
    close(DupesOut0);

    my $cmd1 = 'fgrep '.$amkeys.' '.$outfilereg.' | fgrep -f '.$dupesout0.' | cut -f8-9 -d\|   | awk \' FS="|" { print $2 "|" $1 } \' '; 
    $cmd1 .= ' |  sort | fgrep -i "c:\windows\system32" | grep -e "exe$" ';
    #print "$cmd1\n";
    open(DupesOut1, '>', $dupesout1) or die "Could not open file '$dupesout1' $!";
    open(FND, "$cmd1 |" )  or die "Error with execution: $!";
    while ( defined( my $line = <FND> )  ) {
         chomp($line);
         print DupesOut1 "$line\n";
    }
    close(FND);
    close(DupesOut1);    

    open (FILE1, $dupesout1);
    open (DupesOutreview, '>', $dupesoutreview) or die "Could not open file '$dupesoutreview' $!";
    my %hash;
    while (my $line=<FILE1>) {
       chomp $line;
       #print $line,"\n";
       (my $word1,my $word2) = split /\|/, $line;
       #print "$word1  $word2\n";
       if (exists($hash{$word1})) {
            if ($word2 ne $hash{$word1}) {
              #print "Hash match\n";
              print DupesOutreview "Hash match: $word1  $word2\n";
              print DupesOutreview "      Hash: $word1  $hash{$word1}\n";
            }
          } else {
            $hash{$word1} = $word2;
       }
    }
    close(FILE1);
    close(DupesOutreview);
}


#=============================================================================================
# Process
#=============================================================================================
sub process {

#    * ·        $_ contains the current filename within the directory
#    * ·        $File::Find::dir contains the current directory name
#    * ·        $File::Find::name contains $File::Find::dir/$_

     my $step = 0;
     my ($mntdrive,$outfile) = @_;
     my $outfilereg = $outfile . ".txt";

     my $outfilensrl = $outfile . ".nsrl_nomatch";
     my $outfilefreq = $outfile . ".freq";
     my $outfiledistil = $outfile . ".distil";
     
     
     my $rblistopt = getreviewdb();
     
     print "\n\nStep: $step\n";  
     my $outfilesha = $outfile . "_Step_".$step. ".sha";
     regrip_sha($step,$outfilereg,$mntdrive,$regrip,$regrip_amcache_plugin,$outfile);
     gethash($step,$outfilereg,$outfilesha);
     
     #Step 1
     $step++;
     print "\n\nStep: $step\n";
     my $outfiledistilnsrl = $outfile ."_Step_".$step. ".nsrl_distil";
     run_nsrl($step,$outfilesha,$outfile,$outfiledistilnsrl,$ir_file_distil,$ir_file_distil_nsrl,$ir_file_distil_reviewlist,$ir_file_distil_op);
     
     #Step 2 OS NSRL Distill
     $step++;
     print "\n\nStep: $step\n";
     my $nsrlappoutfile = $outfile."_Step_".$step."_match_apptype.txt";     
     gen_nsrl_categories($step,$outfiledistilnsrl,$nsrlappoutfile,$rblistopt);


     #Step 3
     $step++;
     print "\n\nStep $step\n";
     my $nsrlsha1 = $outfile."_Step_".$step."_match_sha1.txt";
     pull_sha1($step,$nsrlsha1,$outfiledistilnsrl);

     #Step 4
     $step++; 
     print "\n\nStep $step\n";
     my $nomatchlines = $outfile."_Step_".$step."_nomatch_nsrl.txt";    
     freq_analysis($step,$nomatchlines,$outfilereg,$nsrlsha1);


     #Step 5  OS Distill Filecheck
     $step++;  
     print "\n\nStep $step\n";
     my $outfiledistilfilecheck = $outfile ."_Step_".$step. ".filecheck_distil";
     distill($step,$ir_file_distil,$nomatchlines,$outfiledistilfilecheck,$ir_file_distil_opt,$ir_file_distil_filecheck,$rblistopt);
     print "** NOTE: Review ".$outfiledistilfilecheck."_nomatch.txt as the final product.\n";
     
     #Step 6  SHA1 Dupes
     $step++;  
     print "\n\nStep $step\n";
     my $dupesout0 = $outfile ."_Step_".$step. ".dupes0";
     my $dupesout1 = $outfile ."_Step_".$step. ".dupes1";
     my $dupesoutreview = $outfile ."_Step_".$step. ".dupes_review";
     dupes($step,$outfilereg,$dupesout0,$dupesout1,$dupesoutreview);
     print "** NOTE: Review ".$dupesoutreview." for duplicate SHA1/file names and stickey keys.\n";
   

          
}
#=============================================================================================


#=============================================================================================

GetOptions ("mntdrive=s"   => \$mntdrive      # output directory
           ) ||  pod2usage(-verbose => 0);
                      
    pod2usage(-verbose => 1)  if ($opt_help);
    pod2usage(-verbose => 2)  if ($opt_man);
    pod2usage( { -message => q{Mandatory arguement '--mntdrive' is missing}
                 -exitval => 1,
                 -verbose => 1 }
        ) unless ($mntdrive);


#=============================================================================================
# Read in config file
#=============================================================================================
$Config = Config::Tiny->read( $config );


if ($config eq ""){
  ($filename, $directories, $suffix) = fileparse(abs_path($0));
  $config = $directories."plugins.ini";
}

my $Config = Config::Tiny->read( $config );
if (defined $config) {
    $savedirconfig=$Config->{MassTriage}->{savedir};
    $nsrl=$Config->{MassTriage}->{nsrl};
    $nsrlopts=$Config->{MassTriage}->{nsrlopts};
    $nsrldb=$Config->{MassTriage}->{nsrldb};
    $ir_file_distil=$Config->{MassTriage}->{ir_file_distil};
    $ir_file_distil_filecheck=$Config->{MassTriage}->{ir_file_distil_filecheck}; 
    $ir_file_distil_nsrl=$Config->{MassTriage}->{ir_file_distil_nsrl}; 
    $ir_file_distil_reviewlist=$Config->{MassTriage}->{ir_file_distil_reviewlist};
    $ir_file_distil_opt=$Config->{MassTriage}->{ir_file_distil_opt};
    $regrip=$Config->{MassTriage}->{regrip};
    $regrip_amcache_plugin=$Config->{MassTriage}->{regrip_amcache_plugin};
    $wbamcache=$Config->{MassTriage}->{wbamcache};
  } else {
    print "Need a working config.ini file.\n";
    exit 1;
}
#=============================================================================================
#=============================================================================================
# Setup environment to begin work
#=============================================================================================
my $dircwd = getcwd();
my $abs_path = abs_path();
chomp($dircwd);



$savedir = $dircwd . "/" . $savedirconfig. "/amcache";
my $outfile = $savedir."/"."amcache_".$ymd;

$dir = $dircwd;
print "Processing Amcache files: $mntdrive\n";
print "Saving output to: $savedir\n";
print "Amcache processing files start with: $outfile\n";
print "Config File Used: $config\n";
print "Note: This plugin will recreate the directory structure in the save directory for any processed file.\n";
#chdir($dir) or die "Cannot change directory to $dir -- Error: $!";

#Creating the save directory
unless(-e $savedir or File::Path::Tiny::mk($savedir)) {
        die "Unable to create $savedir\n";
}
#=============================================================================================

#=============================================================================================
# Start of plugin code
#=============================================================================================


#Find the amcache files
process($mntdrive,$outfile);



__END__

=head1 ntfslinker.pl

Image device

=head1 SYNOPSIS

ntfslinker.pl [options] [file ...]

Options:

--mntdrive     Where output date should go and where image is mounted (MANDATORY)

--help       Brief help message

--man        Full documentation

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<sample.pl> will 
=cut
