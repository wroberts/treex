package Treex::Core::Run;
use Treex::Moose;
use Treex::Core;
use MooseX::SemiAffordanceAccessor;
with 'MooseX::Getopt';

use Cwd;

has 'save' => (
    traits        => ['Getopt'],
    cmd_aliases   => 's',
    is            => 'rw', isa => 'Bool', default => 0,
    documentation => 'save all documents',
);

has 'quiet' => (
    traits      => ['Getopt'],
    cmd_aliases => 'q',
    is          => 'rw', isa => 'Bool', default => 0,
    trigger => sub { Treex::Core::Log::set_error_level('FATAL'); },
    documentation => q{Warning, info and debug messages are surpressed. Only fatal errors are reported.},
);

has 'error_level' => (
    traits        => ['Getopt'],
    cmd_aliases   => 'e',
    is            => 'rw', isa => 'ErrorLevel', default => 'INFO',
    trigger       => sub { Treex::Core::Log::set_error_level($_[1]); },
    documentation => q{Possible error levels: ALL=0, DEBUG=1, INFO=2, WARN=3, FATAL=4},
);


has 'lang' => (
    traits        => ['Getopt'],
    cmd_aliases   => ['language', 'L'],
    is            => 'rw', isa => 'LangCode',
    documentation => q{shortcut for adding "SetGlobal language=xy" at the beginning of the scenario},
);

has 'selector' => (
    traits        => ['Getopt'],
    cmd_aliases   => 'S',
    is            => 'rw', isa => 'Selector',
    documentation => q{shortcut for adding "SetGlobal selector=xy" at the beginning of the scenario},
);


has 'filelist' => (
    traits        => ['Getopt'],
    cmd_aliases   => 'l',
    is            => 'rw', isa => 'Str',
    documentation => 'TODO load a list of treex files from a file',
);

# treex -h should not print "Unknown option: h" before the usage.
has 'help' => ( 
    traits      => ['Getopt'],
    cmd_aliases => 'h',
    is          => 'ro', isa => 'Bool', default => 0,
    documentation => q{Print usage info},
);


has 'filenames' => (
    traits        => ['NoGetopt'],
    is            => 'rw',
    isa           => 'ArrayRef[Str]',
    documentation => 'treex file names',
);

has 'glob' => (
    traits        => ['Getopt'],
    cmd_aliases   => 'g',
    is            => 'rw',
    isa           => 'Str',
    documentation => q{Input file mask whose expansion is to Perl, e.g. --glob '*.treex'},
);

has 'scenario' => (
    traits        => ['NoGetopt'],
    is            => 'rw', isa => 'Treex::Core::Scenario',
    documentation => 'scenario object',
);

has 'parallel' => (
    traits        => ['Getopt'],
    cmd_aliases   => 'p',
    is            => 'rw',
    isa           => 'Bool',
    default       => 0,
    documentation => 'Parallelize the task on SGE cluster (using qsub).',
);

has 'jobs' => (
    traits        => ['Getopt'],
    cmd_aliases   => 'j',
    is            => 'ro',
    isa           => 'Int',
    default       => 10,
    documentation => 'Number of jobs for parallelization, default 10. Requires -p.',
);

has 'jobindex' => (
    traits        => ['Getopt'],
    is            => 'ro',
    isa           => 'Int',
    documentation => 'Not to be used manually. If number of jobs is set to J and modulo set to M, only I-th files fulfilling I mod J == M are processed.',
);

has 'outdir' => (
    traits        => ['Getopt'],
    is            => 'ro',
    isa           => 'Str',
    documentation => 'Not to be used manually. Dictory for collecting standard and error outputs in parallelized processing.',
);


has 'qsub' => (
    traits        => ['Getopt'],
    is            => 'ro',
    isa           => 'String',
    documentation => 'Additional parameters passed to qsub. Requires -p.',
);

has 'local' => (
    traits        => ['Getopt'],
    is            => 'ro',
    isa           => 'Bool',
    documentation => 'Run jobs locally (might help with multi-core machines). Requires -p.',
);


has 'command' => (
    is            => 'rw',
    traits        => ['NoGetopt'],
    documentation => 'Command by which treex was executed (if executed from command line)',
);

has 'argv' => (
    is            => 'rw',
    traits        => ['NoGetopt'],
    documentation => 'reference to @ARGV (if executed from command line)'
);

sub _usage_format {
    return "usage: %c %o scenario [-- treex_files]\nscenario is a sequence of blocks or *.scen files\noptions:";
}

sub BUILD {

    # more complicated tests on consistency of options will be place here
    my ($self) = @_;

    if ($self->jobindex) {
	_redirect_output($self->outdir,0,$self->jobindex);
    }

    my @file_sources;
    if ( $self->filelist ) {
        push @file_sources, "filelist option";
    }
    if ( $self->filenames ) {
        push @file_sources, "files after --";
    }
    if ( $self->glob ) {
        push @file_sources, "glob option";
    }
    if ( @file_sources > 1 ) {
        log_fatal "At most one way to specify input files can be used. You combined " . ( join " and ", @file_sources ) . ".";

    }

    # 'require' can't be changed to 'imply', since the number of jobs has a default value
    if ( ( $self->qsub or $self->jobindex ) and not $self->parallel ) {
        log_fatal "Options --qsub and --jobindex require --parallel";
    }


}

sub execute {
    my ($self) = @_;

    if ( $self->parallel and not defined $self->jobindex ) {
        log_info "Parallelized execution. This process is the head coordinating " . $self->jobs . " server processes.";
        $self->_execute_on_cluster();
    }

    # non-parallelized execution, or one of distributed processes
    else {
        if ( $self->parallel ) {
            log_info "Parallelized execution. This process is one out of " . $self->jobs . " server processes, jobindex==" . $self->jobindex;
        }
        else {
            log_info "Local (single-process) execution.";
        }
        $self->_execute_locally();
    }

}

sub _execute_locally {
    my ($self) = @_;
    my $scen_str = join ' ', @{ $self->extra_argv };

    # input data files can be specified in different ways
    if ( $self->glob ) {
	my $mask = $self->glob;
	$mask =~ s/^['"](.+)['"]$/$1/;
        my @files = glob $mask;
        log_fatal 'No files matching mask $mask' if @files == 0;
        $self->set_filenames( \@files );
    }
    elsif ( $self->filelist ) {
        open my $FL, "<:utf8", $self->filelist or log_fatal "Cannot open file list " . $self->filelist;
        my @files;
        while (<$FL>) {
            chomp;
            push @files, $_;
        }
        log_fatal 'No files matching mask \'' . $self->glob . '\'\n' if @files == 0;
        $self->set_filenames( \@files );
    }

    # some command line options are just shortcuts for blocks; the blocks are added to the scenario now
    if ( $self->filenames ) {
        log_info "Block Read added to the beginning of the scenario.";
        $scen_str = 'Read from=' . join( ',', @{ $self->filenames } ) . " $scen_str";
    }

    if ( $self->save ) {
        log_info "Block Write::Treex added to the end of the scenario.";
        $scen_str .= ' Write::Treex';
    }

    if ( $self->lang ) {
        $scen_str = 'SetGlobal language=' . $self->lang . " $scen_str";
    }

    if ( $self->selector ) {
        $scen_str = 'SetGlobal selector=' . $self->selector . " $scen_str";
    }


    if ( $self->outdir ) {
        $scen_str = 'SetGlobal outdir=' . $self->outdir . " $scen_str";
    }

    my $scenario = Treex::Core::Scenario->new(
        {   from_string => $scen_str,
            jobs        => $self->jobs,
            jobindex      => $self->jobindex,
	    outdir      => $self->outdir,
        }
    );

    $self->set_scenario($scenario);
    $self->scenario->run();
}

sub _execute_on_cluster {
    my ($self) = @_;

    my $counter;
    my $directory;

    do {
        $counter++;
        $directory = sprintf "%03d-cluster-run", $counter;
        }
        while ( -d $directory );

    log_info "Creating working directory $directory";
    mkdir $directory or log_fatal $!;
    foreach my $subdir (qw(output scripts)) {
        mkdir "$directory/$subdir" or log_fatal $!;
    }

    my @sge_job_numbers;
    $SIG{INT} =
        sub {
            log_info "Caught Ctrl-C, all jobs will be deleted";
            foreach my $job (@sge_job_numbers) {
                log_info "Deleting job $job";
                system "qdel $job";
            }
            log_info "You may want to inspect generated files in $directory/output";
            exit;
        };

    foreach my $jobnumber ( 1 .. $self->jobs ) {
        my $script_filename = "$directory/scripts/job" . sprintf( "%03d", $jobnumber ) . ".sh";
        open J, ">", $script_filename;
        print J "#!/bin/bash\n";
        print J "echo This is debugging output of script $jobnumber, shell \$SHELL\n";
        print J "cd " . (Cwd::cwd) . "\n";
	print J "touch $directory/output/startedjob-$jobnumber\n";
        print J "source ".Treex::Core::Config::lib_core_dir()."/../../../../config/init_devel_environ.sh\n"; # temporary hack !!!
        print J "treex --jobindex=$jobnumber --outdir=$directory/output " . ( join " ", @{$self->argv} ) .
            " 2>$directory/output/joberror-$jobnumber\n";
	print J "touch $directory/output/finishedjob-$jobnumber\n";
        close J;
        chmod 0777, $script_filename;

        if ($self->local) {
	    log_info "$script_filename executed locally";
            system "$script_filename &";
        }
        else {
	    log_info "$script_filename submitted to the cluster";

            open my $QSUB, "qsub -cwd -e $directory/output/ -S /bin/bash $script_filename |";

            my $firstline = <$QSUB>;
            chomp $firstline;
            if ($firstline =~ /job (\d+)/) {
                push @sge_job_numbers, $1;
            }
            else {
                log_fatal 'Job number not detected after the attempt at submitting the job. '.
                    'Perhaps it was not possible to submit the job. See files in $directory/output';
            }
        }
    }

    log_info "Waiting for all jobs to be started...";
    while ( (scalar (() = glob "$directory/output/startedjob-*")  ) < $self->jobs) {  # force list context
	sleep(1);
    }

    log_info "All jobs started. Waiting for them to be finished...";

    my $current_file_number = 1;
    my $total_file_number;

    STDOUT->autoflush(1);
    STDERR->autoflush(1);

    my $all_finished;


  WAIT_LOOP:
    while ( not defined $total_file_number or $current_file_number <= $total_file_number) {

        my $filenumber_file = "$directory/output/filenumber";
        if (not defined $total_file_number and -f $filenumber_file) {
            open ( my $N, $filenumber_file);
            $total_file_number = <$N>;
            log_info "Total number of files to be processed (reported by job 1): $total_file_number";
        }

	$all_finished ||= (scalar(() = glob "$directory/output/finishedjob*") == $self->jobs);
	my $current_finished = ($all_finished ||
				(-f "$directory/output/".sprintf("%07d",$current_file_number).".finished"));

	if ($current_finished) {
	    foreach my $stream (qw(stdout stderr)) {
		my $mask = "$directory/output/".sprintf("%07d",$current_file_number)."*.$stream";
		my ($filename) = glob $mask;

		if ($stream eq 'stdout' and not defined $filename) {
		    sleep 1;
		    next WAIT_LOOP;
		}

		log_fatal "There should have be a file matching mask $mask" if not defined $filename;

		open my $FILE, $filename or log_fatal $!;
		if ($stream eq "stdout") {
		    print $_ while <$FILE>;
		}
		else {
		    print STDERR $_ while <$FILE>;
		}
	    }
	    $current_file_number++;
	}

	else {
	    log_info "Waiting for processing document ".
                ($current_file_number)." out of ".(defined $total_file_number?$total_file_number:'?')." ...";
	    sleep 1;
	}

    }

    log_info "All jobs finished.";

}

sub _redirect_output {
    my ($outdir,$filenumber,$jobindex) = @_;

    my $stem =  $outdir."/".sprintf("%07d",$filenumber)."-".sprintf("%03d",$jobindex);
    open OUTPUT, '>', "$stem.stdout" or die $!;  # where will these messages go to, before redirection?
    open ERROR,  '>', "$stem.stderr"  or die $!;
    STDOUT->fdopen( \*OUTPUT, 'w' ) or die $!;
    STDERR->fdopen( \*ERROR,  'w' ) or die $!;
    STDOUT->autoflush(1);
#    $|=1;
}




use List::MoreUtils qw(first_index);
use Exporter;
use base 'Exporter';
our @EXPORT = qw(treex);


# not a method !
sub treex {

    my $arguments = shift; # ref to array of arguments, or a string containing all arguments as on the command line

    if (ref($arguments) eq "ARRAY") {

	@ARGV = map { # dirty!!!, god knows why spaces in arguments are not processed correctly if they come from command line
	    if (/^(\S+=)(.+ .+)$/) {
		split(/ /,"$1'$2'");
	    }
	    else {
	        $_;
	    }
	} @$arguments;

	my $idx   = first_index {$_ eq '--'} @ARGV;
	my %args;
	$args{command} = join " ",@ARGV;
	$args{argv} = \@ARGV;
	$args{filenames} = [splice @ARGV, $idx+1] if $idx != -1;
	my $app = Treex::Core::Run->new_with_options(\%args);
	$app->execute();

    }

    elsif (defined $arguments) {
	treex( [ grep {$_} split(/\s/,$arguments) ] );
    }

    else {
	log_fatal "Unspecified arguments for running treex.";
    }
}

1;
