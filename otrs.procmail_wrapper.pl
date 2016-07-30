#!/usr/bin/perl
#############################
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#############################
# Developer: Giovanni Mellini
# Contact: giovanni (dot) mellini (at) gmail (dot) com

#############################
# Email handling
use Email::Simple;
local $/;
# Tmp file
use File::Temp qw(tempfile);
# Syslog support
use Sys::Syslog qw(:DEFAULT setlogsock);
use File::Basename;

#############################
# !! MODIFY HERE USING YOUR SPECIFIC ENVIRONMNET VALUES !!
# Config vars - the same var names OTRS use
my $TicketHook = "Ticket";
my $TicketHookDivider = "-";
my $SystemID = "77";
# Program to be executed via system call
# /usr/bin/procmail is default for Ubuntu installation
my $ExternalProgram = "/usr/bin/procmail";

#############################
# Program starts here

# Open syslog
openlog(basename($0), "pid", "local3");

# Get command line parameters for external program
foreach my $arg (@ARGV) {
	$ExternalProgram .= " $arg";
}

# Read coming email from STDIN and write to file
my $tmp_file = new File::Temp( UNLINK => 1 );
print "Writing email to tmp file: $tmp_file\n";
open (FILEW, '>', $tmp_file);
while (<STDIN>) {
	print FILEW $_;
}
close FILEW;

# save email to a string to have better performance with Email::Simple (as documentation states)
open (FILER, $tmp_file);
binmode FILER;
my $text=<FILER>;
close FILER;
my $email = Email::Simple->new($text);

# Get Subject header from email
my $subj_header = $email->header("Subject");
syslog("info", "Email Subject: $subj_header");
print "Subject: $subj_header\n";

# parse Subject and save unique ticket identifiers that match Ticket regexp in an array
my @tkt_array_from_subject = $subj_header =~ /\Q$TicketHook$TicketHookDivider\E(\d{8}$SystemID\d{4,40})/g;
my %seen;
my @tkt_array = grep { ! $seen{$_}++ } @tkt_array_from_subject;
my $tkt_count = @tkt_array;
syslog("info", "Number of unique ticket references in Subject: $tkt_count");
print "Number of unique ticket references in Subject: $tkt_count\n";

syslog("info", "External program called: $ExternalProgram");
print "External program called: $ExternalProgram\n";

# If more than 2 tickets in the Subject process them and create new emails to deliver
if ($tkt_count>=2) {
	foreach my $tkt (@tkt_array) {
		# iterate on subject to remove ticker other than $tkt
		print "\nRemove Ticket other than $TicketHook$TicketHookDivider$tkt from Subject\n";
		my $new_subj_header = $subj_header;
		foreach my $tkt_to_be_removed (@tkt_array) {
			if ($tkt_to_be_removed != $tkt) {
				print "- removing $TicketHook$TicketHookDivider$tkt_to_be_removed from Subject\n";
				my $tmp = $new_subj_header =~ s/$TicketHook$TicketHookDivider$tkt_to_be_removed//gr;
				$new_subj_header = $tmp;
			}
		}
		$email->header_set("Subject", $new_subj_header);

		# write to tmp file new email and send
		my $tmp_file_mod = new File::Temp( UNLINK => 1 );
		open (FILEW2, '>', $tmp_file_mod);
		print FILEW2 $email->as_string;
		close FILEW2;

		syslog("info", "Sending with new Subject: $new_subj_header");
		print "Sending with new Subject: $new_subj_header\n";
		my @args = ("$ExternalProgram < $tmp_file_mod");
		system(@args);
		if ($? != 0) {
			syslog("err", "[ERROR] Problem running $ExternalProgram: exit code $?, error msg $!");
			print "[ERROR] Problem running $ExternalProgram: exit code $?, error msg $!\n";
		}

		# clean
		unlink $tmp_file_mod;
	}
# else ask external program without modification
} else {
	print "Sending to $ExternalProgram with unmodified Subject\n";
	syslog("info", "Sending to $ExternalProgram with unmodified Subject");
	my @args = ("$ExternalProgram < $tmp_file");
	system(@args);
	if ($? != 0) {
		syslog("err", "[ERROR] Problem running $ExternalProgram: exit code $?, error msg $!");
		print "[ERROR] Problem running $ExternalProgram: exit code $?, error msg $!\n";
	}
}

# close syslog
closelog( );

# Remove temp file and clean
unlink $tmp_file;

# Bye!
exit 0;
