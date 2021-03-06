dnl Try to detect the type of the third arg to getsockname() et al
AC_DEFUN([LSH_TYPE_SOCKLEN_T],
[AH_TEMPLATE([socklen_t], [Length type used by getsockopt])
AC_CACHE_CHECK([for socklen_t in sys/socket.h], ac_cv_type_socklen_t,
[AC_EGREP_HEADER(socklen_t, sys/socket.h,
  [ac_cv_type_socklen_t=yes], [ac_cv_type_socklen_t=no])])
if test $ac_cv_type_socklen_t = no; then
        AC_MSG_CHECKING(for AIX)
        AC_EGREP_CPP(yes, [
#ifdef _AIX
 yes
#endif
],[
AC_MSG_RESULT(yes)
AC_DEFINE(socklen_t, size_t)
],[
AC_MSG_RESULT(no)
AC_DEFINE(socklen_t, int)
])
fi
])

dnl Choose cc flags for compiling position independent code
dnl FIXME: Doesn't do the right thing when crosscompiling.
AC_DEFUN([LSH_CCPIC],
[AC_REQUIRE([AC_CANONICAL_HOST])dnl
AC_MSG_CHECKING(CCPIC)
AC_CACHE_VAL(lsh_cv_sys_ccpic,[
  if test -z "$CCPIC" ; then
    if test "$GCC" = yes ; then
      case "$host_os" in
	bsdi4.*)	CCPIC="-fPIC" ;;
	bsdi*)		CCPIC="" ;;
	darwin*)	CCPIC="-fPIC" ;;
	# Could also use -fpic, depending on the number of symbol references
	solaris*)	CCPIC="-fPIC" ;;
	cygwin*)	CCPIC="" ;;
	mingw32*)	CCPIC="" ;;
	*)		CCPIC="-fpic" ;;
      esac
    else
      case "$host_os" in
	darwin*)	CCPIC="-fPIC" ;;
        irix*)		CCPIC="-share" ;;
	hpux*)		CCPIC="+z"; ;;
	*freebsd*)	CCPIC="-fpic" ;;
	sco*|sysv4.*)	CCPIC="-KPIC -dy -Bdynamic" ;;
	solaris*)	CCPIC="-KPIC -Bdynamic" ;;
	winnt*)		CCPIC="-shared" ;;
	*)		CCPIC="" ;;
      esac
    fi
  fi
  OLD_CFLAGS="$CFLAGS"
  CFLAGS="$CFLAGS $CCPIC"
  AC_TRY_COMPILE([], [exit(0);],
    lsh_cv_sys_ccpic="$CCPIC", lsh_cv_sys_ccpic='')
  CFLAGS="$OLD_CFLAGS"
])
CCPIC="$lsh_cv_sys_ccpic"
AC_MSG_RESULT($CCPIC)])

dnl LSH_PATH_ADD(path-id, directory)
AC_DEFUN([LSH_PATH_ADD],
[AC_MSG_CHECKING($2)
ac_exists=no
if test -d "$2/." ; then
  ac_real_dir=`cd $2 && pwd`
  if test -n "$ac_real_dir" ; then
    ac_exists=yes
    for old in $1_REAL_DIRS ; do
      ac_found=no
      if test x$ac_real_dir = x$old ; then
        ac_found=yes;
	break;
      fi
    done
    if test $ac_found = yes ; then
      AC_MSG_RESULT(already added)
    else
      AC_MSG_RESULT(added)
      # LDFLAGS="$LDFLAGS -L $2"
      $1_REAL_DIRS="$ac_real_dir [$]$1_REAL_DIRS"
      $1_DIRS="$2 [$]$1_DIRS"
    fi
  fi
fi
if test $ac_exists = no ; then
  AC_MSG_RESULT(not found)
fi
])

dnl LSH_RPATH_ADD(dir)
AC_DEFUN([LSH_RPATH_ADD], [LSH_PATH_ADD(RPATH_CANDIDATE, $1)])

dnl LSH_RPATH_INIT(candidates)
AC_DEFUN([LSH_RPATH_INIT],
[AC_REQUIRE([AC_CANONICAL_HOST])dnl
AC_MSG_CHECKING([for -R flag])
RPATHFLAG=''
case "$host_os" in
  osf1*)		RPATHFLAG="-rpath " ;;
  irix6.*|irix5.*)	RPATHFLAG="-rpath " ;;
  solaris*)
    if test "$TCC" = "yes"; then
      # tcc doesn't know about -R
      RPATHFLAG="-Wl,-R,"
    else
      RPATHFLAG=-R
    fi
    ;;
  linux*|freebsd*)	RPATHFLAG="-Wl,-rpath," ;;
  *)			RPATHFLAG="" ;;
esac

if test x$RPATHFLAG = x ; then
  AC_MSG_RESULT(none)
else
  AC_MSG_RESULT([using $RPATHFLAG])
fi

RPATH_CANDIDATE_REAL_DIRS=''
RPATH_CANDIDATE_DIRS=''

AC_MSG_RESULT([Searching for libraries])

for d in $1 ; do
  LSH_RPATH_ADD($d)
done
])    

dnl Try to execute a main program, and if it fails, try adding some
dnl -R flag.
dnl LSH_RPATH_FIX
AC_DEFUN([LSH_RPATH_FIX],
[if test $cross_compiling = no -a "x$RPATHFLAG" != x ; then
  ac_success=no
  AC_TRY_RUN([int main(int argc, char **argv) { return 0; }],
    ac_success=yes, ac_success=no, :)
  
  if test $ac_success = no ; then
    AC_MSG_CHECKING([Running simple test program failed. Trying -R flags])
dnl echo RPATH_CANDIDATE_DIRS = $RPATH_CANDIDATE_DIRS
    ac_remaining_dirs=''
    ac_rpath_save_LDFLAGS="$LDFLAGS"
    for d in $RPATH_CANDIDATE_DIRS ; do
      if test $ac_success = yes ; then
  	ac_remaining_dirs="$ac_remaining_dirs $d"
      else
  	LDFLAGS="$RPATHFLAG$d $LDFLAGS"
dnl echo LDFLAGS = $LDFLAGS
  	AC_TRY_RUN([int main(int argc, char **argv) { return 0; }],
  	  [ac_success=yes
  	  ac_rpath_save_LDFLAGS="$LDFLAGS"
  	  AC_MSG_RESULT([adding $RPATHFLAG$d])
  	  ],
  	  [ac_remaining_dirs="$ac_remaining_dirs $d"], :)
  	LDFLAGS="$ac_rpath_save_LDFLAGS"
      fi
    done
    RPATH_CANDIDATE_DIRS=$ac_remaining_dirs
  fi
  if test $ac_success = no ; then
    AC_MSG_RESULT(failed)
  fi
fi
])

dnl Like AC_CHECK_LIB, but uses $KRB_LIBS rather than $LIBS.
dnl LSH_CHECK_KRB_LIB(LIBRARY, FUNCTION, [, ACTION-IF-FOUND [,
dnl                  ACTION-IF-NOT-FOUND [, OTHER-LIBRARIES]]])

AC_DEFUN([LSH_CHECK_KRB_LIB],
[AC_CHECK_LIB([$1], [$2],
  ifelse([$3], ,
      [[ac_tr_lib=HAVE_LIB`echo $1 | sed -e 's/[^a-zA-Z0-9_]/_/g' \
     	    -e 'y/abcdefghijklmnopqrstuvwxyz/ABCDEFGHIJKLMNOPQRSTUVWXYZ/'`
        AC_DEFINE_UNQUOTED($ac_tr_lib)
        KRB_LIBS="-l$1 $KRB_LIBS"
      ]], [$3]),
  ifelse([$4], , , [$4
])dnl
, [$5 $KRB_LIBS])
])

dnl LSH_LIB_ARGP(ACTION-IF-OK, ACTION-IF-BAD)
AC_DEFUN([LSH_LIB_ARGP],
[ ac_argp_save_LIBS="$LIBS"
  ac_argp_save_LDFLAGS="$LDFLAGS"
  ac_argp_ok=no
  # First check if we can link with argp.
  AC_SEARCH_LIBS(argp_parse, argp,
  [ LSH_RPATH_FIX
    AC_CACHE_CHECK([for working argp],
      lsh_cv_lib_argp_works,
      [ AC_TRY_RUN(
[#include <argp.h>
#include <stdlib.h>

static const struct argp_option
options[] =
{
  { NULL, 0, NULL, 0, NULL, 0 }
};

struct child_state
{
  int n;
};

static error_t
child_parser(int key, char *arg, struct argp_state *state)
{
  struct child_state *input = (struct child_state *) state->input;
  
  switch(key)
    {
    default:
      return ARGP_ERR_UNKNOWN;
    case ARGP_KEY_END:
      if (!input->n)
	input->n = 1;
      break;
    }
  return 0;
}

const struct argp child_argp =
{
  options,
  child_parser,
  NULL, NULL, NULL, NULL, NULL
};

struct main_state
{
  struct child_state child;
  int m;
};

static error_t
main_parser(int key, char *arg, struct argp_state *state)
{
  struct main_state *input = (struct main_state *) state->input;

  switch(key)
    {
    default:
      return ARGP_ERR_UNKNOWN;
    case ARGP_KEY_INIT:
      state->child_inputs[0] = &input->child;
      break;
    case ARGP_KEY_END:
      if (!input->m)
	input->m = input->child.n;
      
      break;
    }
  return 0;
}

static const struct argp_child
main_children[] =
{
  { &child_argp, 0, "", 0 },
  { NULL, 0, NULL, 0}
};

static const struct argp
main_argp =
{ options, main_parser, 
  NULL,
  NULL,
  main_children,
  NULL, NULL
};

int main(int argc, char **argv)
{
  struct main_state input = { { 0 }, 0 };
  char *v[2] = { "foo", NULL };

  argp_parse(&main_argp, 1, v, 0, NULL, &input);

  if ( (input.m == 1) && (input.child.n == 1) )
    return 0;
  else
    return 1;
}
], lsh_cv_lib_argp_works=yes,
   lsh_cv_lib_argp_works=no,
   lsh_cv_lib_argp_works=no)])

  if test x$lsh_cv_lib_argp_works = xyes ; then
    ac_argp_ok=yes
  else
    # Reset link flags
    LIBS="$ac_argp_save_LIBS"
    LDFLAGS="$ac_argp_save_LDFLAGS"
  fi])

  if test x$ac_argp_ok = xyes ; then
    ifelse([$1],, true, [$1])
  else
    ifelse([$2],, true, [$2])
  fi   
])

dnl LSH_GCC_ATTRIBUTES
dnl Check for gcc's __attribute__ construction

AC_DEFUN([LSH_GCC_ATTRIBUTES],
[AC_CACHE_CHECK(for __attribute__,
	       lsh_cv_c_attribute,
[ AC_TRY_COMPILE([
#include <stdlib.h>

static void foo(void) __attribute__ ((noreturn));

static void __attribute__ ((noreturn))
foo(void)
{
  exit(1);
}
],[],
lsh_cv_c_attribute=yes,
lsh_cv_c_attribute=no)])

AH_TEMPLATE([HAVE_GCC_ATTRIBUTE], [Define if the compiler understands __attribute__])
if test "x$lsh_cv_c_attribute" = "xyes"; then
  AC_DEFINE(HAVE_GCC_ATTRIBUTE)
fi

AH_BOTTOM(
[#if __GNUC__ && HAVE_GCC_ATTRIBUTE
# define NORETURN __attribute__ ((__noreturn__))
# define PRINTF_STYLE(f, a) __attribute__ ((__format__ (__printf__, f, a)))
# define UNUSED __attribute__ ((__unused__))
#else
# define NORETURN
# define PRINTF_STYLE(f, a)
# define UNUSED
#endif
])])

# Check for alloca, and include the standard blurb in config.h
AC_DEFUN([LSH_FUNC_ALLOCA],
[AC_FUNC_ALLOCA
AC_CHECK_HEADERS([malloc.h])
AH_BOTTOM(
[/* AIX requires this to be the first thing in the file.  */
#ifndef __GNUC__
# if HAVE_ALLOCA_H
#  include <alloca.h>
# else
#  ifdef _AIX
 #pragma alloca
#  else
#   ifndef alloca /* predefined by HP cc +Olibcalls */
char *alloca ();
#   endif
#  endif
/* Needed for alloca on windows */
#  if HAVE_MALLOC_H
#   include <malloc.h>
#  endif
# endif
#else /* defined __GNUC__ */
# if HAVE_ALLOCA_H
#  include <alloca.h>
# else
/* Needed for alloca on windows, also with gcc */
#  if HAVE_MALLOC_H
#   include <malloc.h>
#  endif
# endif
#endif
])])

AC_DEFUN([LSH_FUNC_STRERROR],
[AC_CHECK_FUNCS(strerror)
AH_BOTTOM(
[#if HAVE_STRERROR
#define STRERROR strerror
#else
#define STRERROR(x) (sys_errlist[x])
#endif
])])

AC_DEFUN([LSH_FUNC_STRSIGNAL],
[AC_CHECK_FUNCS(strsignal)
AC_CHECK_DECLS([sys_siglist, _sys_siglist])
AH_BOTTOM(
[#if HAVE_STRSIGNAL
# define STRSIGNAL strsignal
#else /* !HAVE_STRSIGNAL */
# if HAVE_DECL_SYS_SIGLIST
#  define STRSIGNAL(x) (sys_siglist[x])
# else
#  if HAVE_DECL__SYS_SIGLIST
#   define STRSIGNAL(x) (_sys_siglist[x])
#  else
#   define STRSIGNAL(x) "Unknown signal"
#   if __GNUC__
#    warning Using dummy STRSIGNAL
#   endif
#  endif
# endif
#endif /* !HAVE_STRSIGNAL */
])])

dnl LSH_MAKE_CONDITIONAL(symbol, test)
AC_DEFUN([LSH_MAKE_CONDITIONAL],
[if $2 ; then
  IF_$1=''
  UNLESS_$1='# '
else
  IF_$1='# '
  UNLESS_$1=''
fi 
AC_SUBST(IF_$1)
AC_SUBST(UNLESS_$1)])

dnl LSH_DEPENDENCY_TRACKING

dnl Defines compiler flags DEP_FLAGS to generate dependency
dnl information, and DEP_PROCESS that is any shell commands needed for
dnl massaging the dependency information further. Dependencies are
dnl generated as a side effect of compilation. Dependency files
dnl themselves are not treated as targets.

AC_DEFUN([LSH_DEPENDENCY_TRACKING],
[AC_ARG_ENABLE(dependency_tracking,
  AC_HELP_STRING([--disable-dependency-tracking],
    [Disable dependency tracking. Dependency tracking doesn't work with BSD make]),,
  [enable_dependency_tracking=yes])

DEP_FLAGS=''
DEP_PROCESS='true'
if test x$enable_dependency_tracking = xyes ; then
  if test x$GCC = xyes ; then
    gcc_version=`gcc --version | head -1`
    case "$gcc_version" in
      2.*|*[[!0-9.]]2.*)
        enable_dependency_tracking=no
        AC_MSG_WARN([Dependency tracking disabled, gcc-3.x is needed])
      ;;
      *)
        DEP_FLAGS='-MT $[]@ -MD -MP -MF $[]@.d'
        DEP_PROCESS='true'
      ;;
    esac
  else
    enable_dependency_tracking=no
    AC_MSG_WARN([Dependency tracking disabled])
  fi
fi

if test x$enable_dependency_tracking = xyes ; then
  DEP_INCLUDE='include '
else
  DEP_INCLUDE='# '
fi

AC_SUBST([DEP_INCLUDE])
AC_SUBST([DEP_FLAGS])
AC_SUBST([DEP_PROCESS])])

dnl  GMP_TRY_ASSEMBLE(asm-code,[action-success][,action-fail])
dnl  ----------------------------------------------------------
dnl  Attempt to assemble the given code.
dnl  Do "action-success" if this succeeds, "action-fail" if not.
dnl
dnl  conftest.o and conftest.out are available for inspection in
dnl  "action-success".  If either action does a "break" out of a loop then
dnl  an explicit "rm -f conftest*" will be necessary.
dnl
dnl  This is not unlike AC_TRY_COMPILE, but there's no default includes or
dnl  anything in "asm-code", everything wanted must be given explicitly.

AC_DEFUN([GMP_TRY_ASSEMBLE],
[cat >conftest.s <<EOF
[$1]
EOF
gmp_assemble="$CC $CFLAGS $CPPFLAGS -c conftest.s >conftest.out 2>&1"
if AC_TRY_EVAL(gmp_assemble); then
  cat conftest.out >&AC_FD_CC
  ifelse([$2],,:,[$2])
else
  cat conftest.out >&AC_FD_CC
  echo "configure: failed program was:" >&AC_FD_CC
  cat conftest.s >&AC_FD_CC
  ifelse([$3],,:,[$3])
fi
rm -f conftest*
])

dnl  GMP_PROG_CC_FOR_BUILD
dnl  ---------------------
dnl  Establish CC_FOR_BUILD, a C compiler for the build system.
dnl
dnl  If CC_FOR_BUILD is set then it's expected to work, likewise the old
dnl  style HOST_CC, otherwise some likely candidates are tried, the same as
dnl  configfsf.guess.

AC_DEFUN([GMP_PROG_CC_FOR_BUILD],
[AC_REQUIRE([AC_PROG_CC])
if test -n "$CC_FOR_BUILD"; then
  GMP_PROG_CC_FOR_BUILD_WORKS($CC_FOR_BUILD,,
    [AC_MSG_ERROR([Specified CC_FOR_BUILD doesn't seem to work])])
elif test -n "$HOST_CC"; then
  GMP_PROG_CC_FOR_BUILD_WORKS($HOST_CC,
    [CC_FOR_BUILD=$HOST_CC],
    [AC_MSG_ERROR([Specified HOST_CC doesn't seem to work])])
else
  if test $cross_compiling = no ; then
    CC_FOR_BUILD="$CC"  
  else
    for i in gcc cc c89 c99; do
      GMP_PROG_CC_FOR_BUILD_WORKS($i,
        [CC_FOR_BUILD=$i
         break])
    done
    if test -z "$CC_FOR_BUILD"; then
      AC_MSG_ERROR([Cannot find a build system compiler])
    fi
  fi
  if test "$CC_FOR_BUILD" = gcc ; then
    CC_FOR_BUILD="$CC_FOR_BUILD -O -g"
  fi
fi

AC_ARG_VAR(CC_FOR_BUILD,[build system C compiler])
AC_SUBST(CC_FOR_BUILD)
])


dnl  GMP_PROG_CC_FOR_BUILD_WORKS(cc/cflags[,[action-if-good][,action-if-bad]])
dnl  -------------------------------------------------------------------------
dnl  See if the given cc/cflags works on the build system.
dnl
dnl  It seems easiest to just use the default compiler output, rather than
dnl  figuring out the .exe or whatever at this stage.

AC_DEFUN([GMP_PROG_CC_FOR_BUILD_WORKS],
[AC_MSG_CHECKING([build system compiler $1])
# remove anything that might look like compiler output to our "||" expression
rm -f conftest* a.out b.out a.exe a_out.exe
cat >conftest.c <<EOF
#include<stdio.h>
int
main ()
{
  exit(0);
}
EOF
gmp_compile="$1 conftest.c"
cc_for_build_works=no
if AC_TRY_EVAL(gmp_compile); then
  if (./a.out || ./b.out || ./a.exe || ./a_out.exe || ./conftest) >&AC_FD_CC 2>&1; then
    cc_for_build_works=yes
  fi
fi
rm -f conftest* a.out b.out a.exe a_out.exe
AC_MSG_RESULT($cc_for_build_works)
if test "$cc_for_build_works" = yes; then
  ifelse([$2],,:,[$2])
else
  ifelse([$3],,:,[$3])
fi
])

dnl  GMP_PROG_EXEEXT_FOR_BUILD
dnl  -------------------------
dnl  Determine EXEEXT_FOR_BUILD, the build system executable suffix.
dnl
dnl  The idea is to find what "-o conftest$foo" will make it possible to run
dnl  the program with ./conftest.  On Unix-like systems this is of course
dnl  nothing, for DOS it's ".exe", or for a strange RISC OS foreign file
dnl  system cross compile it can be ",ff8" apparently.  Not sure if the
dnl  latter actually applies to a build-system executable, maybe it doesn't,
dnl  but it won't hurt to try.

AC_DEFUN([GMP_PROG_EXEEXT_FOR_BUILD],
[AC_REQUIRE([GMP_PROG_CC_FOR_BUILD])
AC_CACHE_CHECK([for build system executable suffix],
               gmp_cv_prog_exeext_for_build,
[if test $cross_compiling = no ; then
  gmp_cv_prog_exeext_for_build="$EXEEXT"
else
  cat >conftest.c <<EOF
int
main ()
{
  exit (0);
}
EOF
  for i in .exe ,ff8 ""; do
    gmp_compile="$CC_FOR_BUILD conftest.c -o conftest$i"
    if AC_TRY_EVAL(gmp_compile); then
      if (./conftest) 2>&AC_FD_CC; then
        gmp_cv_prog_exeext_for_build=$i
        break
      fi
    fi
  done
  rm -f conftest*
  if test "${gmp_cv_prog_exeext_for_build+set}" != set; then
    AC_MSG_ERROR([Cannot determine executable suffix])
  fi
fi
])
AC_SUBST(EXEEXT_FOR_BUILD,$gmp_cv_prog_exeext_for_build)
])

dnl NETTLE_CHECK_ARM_NEON
dnl ---------------------
dnl Check if ARM Neon instructions should be used.
dnl Obeys enable_arm_neon, which should be set earlier.
AC_DEFUN([NETTLE_CHECK_ARM_NEON],
[if test "$enable_arm_neon" = auto ; then
  if test "$cross_compiling" = yes ; then
    dnl Check if compiler/assembler accepts it,
    dnl without an explicit .fpu neon directive.
    AC_CACHE_CHECK([if assembler accepts Neon instructions],
      nettle_cv_asm_arm_neon,
      [GMP_TRY_ASSEMBLE([
.text
foo:
	vmlal.u32	q1, d0, d1
],
      [nettle_cv_asm_arm_neon=yes],
      [nettle_cv_asm_arm_neon=no])])
    enable_arm_neon="$nettle_cv_asm_arm_neon"
  else
    AC_MSG_CHECKING([if /proc/cpuinfo claims neon support])
    if grep '^Features.*:.* neon' /proc/cpuinfo >/dev/null ; then
      enable_arm_neon=yes
    else
      enable_arm_neon=no
    fi
    AC_MSG_RESULT($enable_arm_neon)
  fi
fi
])

dnl NETTLE_CHECK_IFUNC
dnl ------------------
dnl Check if __attribute__ ((ifunc(...))) works
AC_DEFUN([NETTLE_CHECK_IFUNC],
[AC_REQUIRE([AC_PROG_CC])
AC_CACHE_CHECK([for ifunc support],
  nettle_cv_link_ifunc,
  [AC_LINK_IFELSE([AC_LANG_PROGRAM([
static int
foo_imp(int x)
{
  return 1;
}

typedef void void_func (void);

static void_func *
foo_resolv(void)
{
  return (void_func *) foo_imp;
}

int foo (int x) __attribute__ ((ifunc("foo_resolv")));
],[
  return foo(0);

])],
[nettle_cv_link_ifunc=yes],
[nettle_cv_link_ifunc=no])])
AH_TEMPLATE([HAVE_LINK_IFUNC], [Define if compiler and linker supports __attribute__ ifunc])
if test "x$nettle_cv_link_ifunc" = xyes ; then
  AC_DEFINE(HAVE_LINK_IFUNC)
fi 
])

# ld-version-script.m4 serial 3
dnl Copyright (C) 2008-2014 Free Software Foundation, Inc.
dnl This file is free software; the Free Software Foundation
dnl gives unlimited permission to copy and/or distribute it,
dnl with or without modifications, as long as this notice is preserved.

dnl From Simon Josefsson

# FIXME: The test below returns a false positive for mingw
# cross-compiles, 'local:' statements does not reduce number of
# exported symbols in a DLL.  Use --disable-ld-version-script to work
# around the problem.

# gl_LD_VERSION_SCRIPT
# --------------------
# Check if LD supports linker scripts, and define automake conditional
# HAVE_LD_VERSION_SCRIPT if so.
AC_DEFUN([LD_VERSION_SCRIPT],
[
  AC_ARG_ENABLE([ld-version-script],
    AS_HELP_STRING([--enable-ld-version-script],
      [enable linker version script (default is enabled when possible)]),
      [have_ld_version_script=$enableval], [])
  if test -z "$have_ld_version_script"; then
    AC_MSG_CHECKING([if LD -Wl,--version-script works])
    save_LDFLAGS="$LDFLAGS"
    LDFLAGS="$LDFLAGS -Wl,--version-script=conftest.map"
    cat > conftest.map <<EOF
foo
EOF
    AC_LINK_IFELSE([AC_LANG_PROGRAM([], [])],
                   [accepts_syntax_errors=yes], [accepts_syntax_errors=no])
    if test "$accepts_syntax_errors" = no; then
      cat > conftest.map <<EOF
VERS_1 {
        global: sym;
};

VERS_2 {
        global: sym;
} VERS_1;
EOF
      AC_LINK_IFELSE([AC_LANG_PROGRAM([], [])],
                     [have_ld_version_script=yes], [have_ld_version_script=no])
    else
      have_ld_version_script=no
    fi
    rm -f conftest.map
    LDFLAGS="$save_LDFLAGS"
    AC_MSG_RESULT($have_ld_version_script)
  fi
  if test "$have_ld_version_script" = "yes";then
	EXTRA_LINKER_FLAGS="-Wl,--version-script=libnettle.map"
	AC_SUBST(EXTRA_LINKER_FLAGS)
	EXTRA_HOGWEED_LINKER_FLAGS="-Wl,--version-script=libhogweed.map"
	AC_SUBST(EXTRA_HOGWEED_LINKER_FLAGS)
  fi
])
