package IPC::Pleather;
# ABSTRACT: Easy to use concurrency primitives inspired by Cilk

use strict;
use warnings;
use AnyEvent;
use AnyEvent::Util qw(fork_call);
use IPC::Semaphore;
use IPC::SysV qw(IPC_PRIVATE S_IRUSR S_IWUSR IPC_CREAT IPC_NOWAIT);
use Keyword::Declare;
use Guard;

#-------------------------------------------------------------------------------
# IPC
#-------------------------------------------------------------------------------
our $PID = $$;
our $SEM = IPC::Semaphore->new(IPC_PRIVATE, 1, S_IRUSR|S_IWUSR|IPC_CREAT);
our $DEPTH = 0;

our $SEMGUARD = guard {
  $SEM->remove;
  undef $SEM;
};

sset($AnyEvent::Util::MAX_FORKS);

sub sset { $SEM->setval(0, $_[0]) }
sub sdec { $SEM->op(0, -1, IPC_NOWAIT) }
sub sinc { $SEM->op(0,  1, IPC_NOWAIT) }

sub spawn {
  my ($code, @args) = @_;

  if (!$AnyEvent::CondVar::Base::WAITING && sdec) {
    my $cv = AE::cv;

    fork_call {
      ++$DEPTH;
      my ($code, @args) = @_;
      $code->(@args);
    } $code, @args,
    sub {
      if (@_) {
        $cv->send(@_);
      }
      else {
        eval{ $cv->send($code->(@args)) };
        $@ && $cv->croak($@);
      }
      sinc;
    };

    return $cv;
  }
  else {
    return $code->(@args);
  }
}

#-------------------------------------------------------------------------------
# Keyword expansions
#-------------------------------------------------------------------------------
sub import {
  keyword sync (ScalarVar $var)
  {{{
    <{$var}> = ((ref(<{$var}>) || '') eq 'AnyEvent::CondVar') ? <{$var}>->recv : <{$var}>;
  }}}

  keyword spawn (VarDecl $var, '=', Block $block, CommaList $arg_list, ';')
  {{{
    <{$var}> = IPC::Pleather::spawn(sub <{$block}>, <{$arg_list}>);
  }}}

  keyword spawn (VarDecl $var, '=', Ident $sub, '(', CommaList $arg_list, ')', ';')
  {{{
    spawn <{$var}> = { <{$sub}>(@_) } <{$arg_list}>;
  }}}

  keyword spawn (VarDecl $var, '=', Ident $sub, Var|Statement|CommaList $arg_or_args, ';')
  {{{
    spawn <{$var}> = <{$sub}>(<{$arg_or_args}>);
  }}}
}

1;
