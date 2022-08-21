#!/bin/sh

# Uncomment the following line to override the JVM search sequence
# INSTALL4J_JAVA_HOME_OVERRIDE=
# Uncomment the following line to add additional VM parameters
# INSTALL4J_ADD_VM_PARAMS=


INSTALL4J_JAVA_PREFIX=""
GREP_OPTIONS=""

fill_version_numbers() {
  if [ "$ver_major" = "" ]; then
    ver_major=0
  fi
  if [ "$ver_minor" = "" ]; then
    ver_minor=0
  fi
  if [ "$ver_micro" = "" ]; then
    ver_micro=0
  fi
  if [ "$ver_patch" = "" ]; then
    ver_patch=0
  fi
}

read_db_entry() {
  if [ -n "$INSTALL4J_NO_DB" ]; then
    return 1
  fi
  if [ ! -f "$db_file" ]; then
    return 1
  fi
  if [ ! -x "$java_exc" ]; then
    return 1
  fi
  found=1
  exec 7< $db_file
  while read r_type r_dir r_ver_major r_ver_minor r_ver_micro r_ver_patch r_ver_vendor<&7; do
    if [ "$r_type" = "JRE_VERSION" ]; then
      if [ "$r_dir" = "$test_dir" ]; then
        ver_major=$r_ver_major
        ver_minor=$r_ver_minor
        ver_micro=$r_ver_micro
        ver_patch=$r_ver_patch
        fill_version_numbers
      fi
    elif [ "$r_type" = "JRE_INFO" ]; then
      if [ "$r_dir" = "$test_dir" ]; then
        is_openjdk=$r_ver_major
        is_64bit=$r_ver_micro
        if [ "W$r_ver_minor" = "W$modification_date" ] && [ "W$is_64bit" != "W" ]; then
          found=0
          break
        fi
      fi
    fi
    r_ver_micro=""
  done
  exec 7<&-

  return $found
}

create_db_entry() {
  tested_jvm=true
  version_output=`"$bin_dir/java" $1 -version 2>&1`
  is_gcj=`expr "$version_output" : '.*gcj'`
  is_64bit=`expr "$version_output" : '.*64-Bit\|.*amd64'`
  if [ "$is_gcj" = "0" ]; then
    java_version=`expr "$version_output" : '.*"\(.*\)".*'`
    ver_major=`expr "$java_version" : '\([0-9][0-9]*\).*'`
    ver_minor=`expr "$java_version" : '[0-9][0-9]*\.\([0-9][0-9]*\).*'`
    ver_micro=`expr "$java_version" : '[0-9][0-9]*\.[0-9][0-9]*\.\([0-9][0-9]*\).*'`
    ver_patch=`expr "$java_version" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*[\._]\([0-9][0-9]*\).*'`
  fi
  fill_version_numbers
  if [ -n "$INSTALL4J_NO_DB" ]; then
    return
  fi
  db_new_file=${db_file}_new
  if [ -f "$db_file" ]; then
    awk '$2 != "'"$test_dir"'" {print $0}' $db_file > $db_new_file
    rm "$db_file"
    mv "$db_new_file" "$db_file"
  fi
  dir_escaped=`echo "$test_dir" | sed -e 's/ /\\\\ /g'`
  echo "JRE_VERSION	$dir_escaped	$ver_major	$ver_minor	$ver_micro	$ver_patch" >> $db_file
  echo "JRE_INFO	$dir_escaped	$is_openjdk	$modification_date	$is_64bit" >> $db_file
  chmod g+w $db_file
}

check_date_output() {
  if [ -n "$date_output" -a $date_output -eq $date_output 2> /dev/null ]; then
    modification_date=$date_output
  fi
}

test_jvm() {
  tested_jvm=na
  test_dir=$1
  bin_dir=$test_dir/bin; echo "test_jvm: '\$test_dir/bin' ('$test_dir/bin') was assigned to \$bin_dir"
  java_exc=$bin_dir/java; echo "test_jvm: '\$bin_dir/java' ('$bin_dir/java') assigned to \$java_exec"
  if [ -z "$test_dir" ] || [ ! -d "$bin_dir" ] || [ ! -f "$java_exc" ] || [ ! -x "$java_exc" ]; then echo "[ERROR] test_jvm: \$test_dir ('$test_dir') is empty -OR- \$bin_dir ('$bin_dir') does not exist or is not a direcotry -OR- \$java_exec ('$java_exec') does not exist or is not a file -OR- \$java_exec ('$java_exec') does not exist or is not an executable file."
    return
  fi

  modification_date=0
  date_output=`date -r "$java_exc" "+%s" 2>/dev/null`
  if [ $? -eq 0 ]; then
    check_date_output
  fi
  if [ $modification_date -eq 0 ]; then
    stat_path=`command -v stat 2> /dev/null`
    if [ "$?" -ne "0" ] || [ "W$stat_path" = "W" ]; then
      stat_path=`which stat 2> /dev/null`
      if [ "$?" -ne "0" ]; then
        stat_path=""
      fi
    fi
    if [ -f "$stat_path" ]; then
      date_output=`stat -f "%m" "$java_exc" 2>/dev/null`
      if [ $? -eq 0 ]; then
        check_date_output
      fi
      if [ $modification_date -eq 0 ]; then
        date_output=`stat -c "%Y" "$java_exc" 2>/dev/null`
        if [ $? -eq 0 ]; then
          check_date_output
        fi
      fi
    fi
  fi

  tested_jvm=false
  read_db_entry || create_db_entry $2

  if [ "$ver_major" = "" ]; then
    return;
  fi
  if [ "$ver_major" -lt "17" ]; then
    return;
  elif [ "$ver_major" -eq "17" ]; then
    if [ "$ver_minor" -lt "0" ]; then
      return;
    elif [ "$ver_minor" -eq "0" ]; then
      if [ "$ver_micro" -lt "1" ]; then
        return;
      fi
    fi
  fi

  if [ "$ver_major" = "" ]; then
    return;
  fi
  if [ "$ver_major" -gt "17" ]; then
    return;
  elif [ "$ver_major" -eq "17" ]; then
    if [ "$ver_minor" -gt "0" ]; then
      return;
    elif [ "$ver_minor" -eq "0" ]; then
      if [ "$ver_micro" -gt "999" ]; then
        return;
      fi
    fi
  fi

  app_java_home=$test_dir
}

add_class_path() {
  if [ -n "$1" ] && [ `expr "$1" : '.*\*'` -eq "0" ]; then
    local_classpath="$local_classpath${local_classpath:+:}${1}${2}"
  fi
}


read_vmoptions() {
  vmoptions_file=`eval echo "$1" 2>/dev/null`
  if [ ! -r "$vmoptions_file" ]; then
    vmoptions_file="$prg_dir/$vmoptions_file"
  fi
  if [ -r "$vmoptions_file" ] && [ -f "$vmoptions_file" ]; then
    exec 8< "$vmoptions_file"
    while read cur_option<&8; do
      is_comment=`expr "W$cur_option" : 'W *#.*'`
      if [ "$is_comment" = "0" ]; then
        vmo_classpath=`expr "W$cur_option" : 'W *-classpath \(.*\)'`
        vmo_classpath_a=`expr "W$cur_option" : 'W *-classpath/a \(.*\)'`
        vmo_classpath_p=`expr "W$cur_option" : 'W *-classpath/p \(.*\)'`
        vmo_include=`expr "W$cur_option" : 'W *-include-options \(.*\)'`
        if [ ! "W$vmo_include" = "W" ]; then
            if [ "W$vmo_include_1" = "W" ]; then
              vmo_include_1="$vmo_include"
            elif [ "W$vmo_include_2" = "W" ]; then
              vmo_include_2="$vmo_include"
            elif [ "W$vmo_include_3" = "W" ]; then
              vmo_include_3="$vmo_include"
            fi
        fi
        if [ ! "$vmo_classpath" = "" ]; then
          local_classpath="$i4j_classpath:$vmo_classpath"
        elif [ ! "$vmo_classpath_a" = "" ]; then
          local_classpath="${local_classpath}:${vmo_classpath_a}"
        elif [ ! "$vmo_classpath_p" = "" ]; then
          local_classpath="${vmo_classpath_p}:${local_classpath}"
        elif [ "W$vmo_include" = "W" ]; then
          needs_quotes=`expr "W$cur_option" : 'W.* .*'`
          if [ "$needs_quotes" = "0" ]; then
            vmoptions_val="$vmoptions_val $cur_option"
          else
            if [ "W$vmov_1" = "W" ]; then
              vmov_1="$cur_option"
            elif [ "W$vmov_2" = "W" ]; then
              vmov_2="$cur_option"
            elif [ "W$vmov_3" = "W" ]; then
              vmov_3="$cur_option"
            elif [ "W$vmov_4" = "W" ]; then
              vmov_4="$cur_option"
            elif [ "W$vmov_5" = "W" ]; then
              vmov_5="$cur_option"
            fi
          fi
        fi
      fi
    done
    exec 8<&-
    if [ ! "W$vmo_include_1" = "W" ]; then
      vmo_include="$vmo_include_1"
      unset vmo_include_1
      read_vmoptions "$vmo_include"
    fi
    if [ ! "W$vmo_include_2" = "W" ]; then
      vmo_include="$vmo_include_2"
      unset vmo_include_2
      read_vmoptions "$vmo_include"
    fi
    if [ ! "W$vmo_include_3" = "W" ]; then
      vmo_include="$vmo_include_3"
      unset vmo_include_3
      read_vmoptions "$vmo_include"
    fi
  fi
}


unpack_file() {
  if [ -f "$1" ]; then echo "unpack_file: the file '$1' exists. Assigning value of expression `echo '$1' \| awk '{print substr($0,1,length($0)-5)}'` to \$jar_file..."
    jar_file=`echo "$1" | awk '{ print substr($0,1,length($0)-5) }'`; echo "run_unpack: calling app 'bin/unpack200' with args '-r \"$1\" \"$jar_file\"', printing stdout to /dev/null, and printing stderr to &1..."
    bin/unpack200 -r "$1" "$jar_file" > /dev/null 2>&1

    if [ $? -ne 0 ]; then
      echo "Error unpacking jar files. The architecture or bitness (32/64)"
      echo "of the bundled JVM might not match your machine."
      returnCode=1
      cd "$old_pwd"; echo "run_unpack: working directory was restored to \$old_pwd ('$old_pwd')"
      if [ ! "W $INSTALL4J_KEEP_TEMP" = "W yes" ]; then echo "run_unpack: the value of \$INSTALL4J_KEEP_TEMP is not 'yes'. Recursively and forcefully removing path \$sfx_dir_name ('$sfx_dir_name')..."
        rm -R -f "$sfx_dir_name"
      fi
      exit $returnCode
    else
      chmod a+r "$jar_file"; echo "run_unpack: Read permission granted for \$jar_file ('$jar_file')"
    fi
  fi
}

run_unpack200() {
  if [ -d "$1/lib" ]; then echo "run_unpack: the path '$1/lib' exists and is a directory"
    old_pwd200=`pwd`; echo "run_unpack: \$old_pwd200 was set to working directory"
    cd "$1"; echo "run_unpack: working directory was set to '$1'"; echo "run_unpack: unpacking all files matching 'lib/*.jar.pack'..."
    for pack_file in lib/*.jar.pack
    do
      unpack_file $pack_file
    done; echo "run_unpack: unpacking all files matching 'lib/ext/*.jar.pack'..."
    for pack_file in lib/ext/*.jar.pack
    do
      unpack_file $pack_file
    done
    cd "$old_pwd200"; echo "run_unpack: working directory was set to \$old_pwd200 ('$old_pwd200')"
  fi
}

search_jre() {
  if [ -z "$app_java_home" ]; then echo "search_jre step 1: \$app_java_home is empty. Calling test_jvm() with arg \$INSTALL4J_JAVA_HOME_OVERRIDE ('$INSTALL4J_JAVA_HOME_OVERRIDE')..."
  test_jvm "$INSTALL4J_JAVA_HOME_OVERRIDE"
fi

  if [ -z "$app_java_home" ]; then echo "search_jre step 2: \$app_java_home is still empty."
    if [ -f "$app_home/.install4j/pref_jre.cfg" ]; then echo "search_jre step 2: '$app_home/.install4j/pref_jre.cfg' exists. Assigining content to \$file_jvm_home..."
        read file_jvm_home < "$app_home/.install4j/pref_jre.cfg"; echo "search_jre step 2: The value of \$file_jvm_home is '$file_jvm_home'. Calling test_jvm() with arg '\$file_jvm_home'...".
    test_jvm "$file_jvm_home"
        if [ -z "$app_java_home" ] && [ $tested_jvm = "false" ]; then echo "search_jre step 2: \$app_java_home is still empty. \$tested_jvm is 'false'."
          if [ -f "$db_file" ]; then echo "search_jre step 2: attempting to silently delete \$db_file ('$db_file')..."
  rm "$db_file" 2> /dev/null
          fi; echo "search_jre step 2: Calling test_jvm with arg '\$file_jvm' ('$file_jvm')..."
        test_jvm "$file_jvm_home"
    fi
fi
fi

  if [ -z "$app_java_home" ]; then echo "search_jre step 3: \$app_java_home is still empty. Calling test_jvm() with arg '\$app_home/../jre.bundle/Contents/Home' ('$app_home/../jre.bundle/Contents/Home')."
  test_jvm "$app_home/../jre.bundle/Contents/Home"
    if [ -z "$app_java_home" ] && [ $tested_jvm = "false" ]; then echo "search_jre step 3: \$app_java_home is still empty and \$tested_jvm is false."
      if [ -f "$db_file" ]; then echo "search_jre step 3: attempting to silently delete \$db_file ('$db_file')..."
  rm "$db_file" 2> /dev/null
      fi
    echo "search_jre step 3: Calling test_jvm with arg '\$app_home/../jre.bundle/Contents/Home' ('$app_home/../jre.bundle/Contents/Home')..."; test_jvm "$app_home/../jre.bundle/Contents/Home"
  fi
fi

  if [ -z "$app_java_home" ]; then echo "search_jre step 4: \$app_java_home is still empty."
    if [ "W$INSTALL4J_NO_PATH" != "Wtrue" ]; then echo "search_jre step 4: \$INSTALL4J_NO_PATH is false. Assigning value of expression `command -v java 2\> /dev/null` to \$prg_jvm..."
    prg_jvm=`command -v java 2> /dev/null`
      if [ "$?" -ne "0" ] || [ "W$prg_jvm" = "W" ]; then echo "search_jre step 4: var arg \$? ($?) is unequal to 0 -OR- \$prg_jvm ('$prg_jvm') is empty. Assigning value of expression `which java 2\> /dev/null` to \$prg_jvm..."
      prg_jvm=`which java 2> /dev/null`
        if [ "$?" -ne "0" ]; then echo "search_jre step 4: var arg \$? ($?) is unequal to 0. Assigning empty string to \$prg_jvm..."
        prg_jvm=""
      fi
    fi
      if [ ! -z "$prg_jvm" ] && [ -f "$prg_jvm" ]; then echo "search_jre step 4: \$prg_jvm ('$prg_jvm') is not empty and the file exists."
        old_pwd_jvm=`pwd`; echo "search_jre step 4: current process working directory has been assigned to \$old_pwd_jvm ('$old_pwd_jvm')."
        path_java_bin=`dirname "$prg_jvm"`; echo "search_jre step 4: the path of the parent directory of \$prg_jvm has been assigned to \$path_java_bin ('$path_java_bin')."
        cd "$path_java_bin"; echo "search_jre step 4: the working directory has been set to \$path_java_bin ('$path_java_bin')."
        prg_jvm=java; echo "search_jre step 4: the value of \$java has been assigned to \$prg_jvm ('$prg_jvm')."

        while [ -h "$prg_jvm" ] ; do echo "search_jre step 4: \$prg_jvm ('$prg_jvm') exists and is a symbolic link. This will loop until either condition is false."
        ls=`ls -ld "$prg_jvm"`
        link=`expr "$ls" : '.*-> \(.*\)$'`
        if expr "$link" : '.*/.*' > /dev/null; then
          prg_jvm="$link"
        else
          prg_jvm="`dirname $prg_jvm`/$link"
        fi
      done
        path_java_bin=`dirname "$prg_jvm"`; echo "search_jre step 4: Path of parent directory of \$prg_jvm ('$prg_jvm') was assigned to \$path_java_bin ('$path_java_bin')."
        cd "$path_java_bin"; echo "search_jre step 4: working directory was set to \$path_java_bin ('$path_java_bin')"
        cd ..; echo "search_jre step 4: working directory was set to parent directory"
        path_java_home=`pwd`; echo "search_jre step 4: \$path_java_home was set to working directory ('$path_java_home')"
        cd "$old_pwd_jvm"; echo "search_jre step 4: working directory restored to \$old_pwd_jvm ('$old_pwd_jvm')"; "search_jre step 4: calling test_jvm() with arg \$path_java_home ('$path_java_home')..."
        test_jvm "$path_java_home";
    fi
  fi
fi


  if [ -z "$app_java_home" ]; then echo "search_jre step 5: \$app_java_home is still empty."
    common_jvm_locations="/opt/i4j_jres/* /usr/local/i4j_jres/* $HOME/.i4j_jres/* /usr/bin/java* /usr/bin/jdk* /usr/bin/jre* /usr/bin/j2*re* /usr/bin/j2sdk* /usr/java* /usr/java*/jre /usr/jdk* /usr/jre* /usr/j2*re* /usr/j2sdk* /usr/java/j2*re* /usr/java/j2sdk* /opt/java* /usr/java/jdk* /usr/java/jre* /usr/lib/java/jre /usr/local/java* /usr/local/jdk* /usr/local/jre* /usr/local/j2*re* /usr/local/j2sdk* /usr/jdk/java* /usr/jdk/jdk* /usr/jdk/jre* /usr/jdk/j2*re* /usr/jdk/j2sdk* /usr/lib/jvm/* /usr/lib/java* /usr/lib/jdk* /usr/lib/jre* /usr/lib/j2*re* /usr/lib/j2sdk* /System/Library/Frameworks/JavaVM.framework/Versions/1.?/Home /Library/Internet\ Plug-Ins/JavaAppletPlugin.plugin/Contents/Home /Library/Java/JavaVirtualMachines/*.jdk/Contents/Home/jre /Library/Java/JavaVirtualMachines/*.jre/Contents/Home /Library/Java/JavaVirtualMachines/*.jdk/Contents/Home"; echo "search_jre step 5: multiple paths assigned to \$common_jvm_locations ('$common_jvm_locations')"; echo "search_jre step 5: looping through \$common_jvm_locations..."
  for current_location in $common_jvm_locations
  do
      if [ -z "$app_java_home" ]; then echo "search_jre step 5: \$app_java_home is empty. Calling test_jvm() with arg \$current_location ('$current_location') in \$common_jvm_locations..."
  test_jvm "$current_location"
fi

  done
fi

  if [ -z "$app_java_home" ]; then echo "search_jre step 6: \$app_java_home is still empty. Calling test_jvm() with arg \$JAVA_HOME ('$JAVA_HOME')..."
  test_jvm "$JAVA_HOME"
fi

  if [ -z "$app_java_home" ]; then echo "search_jre step 7: \$app_java_home is still empty. Calling test_jvm() with arg \$JDK_HOME ('$JDK_HOME')..."
  test_jvm "$JDK_HOME"
fi

  if [ -z "$app_java_home" ]; then echo "search_jre step 8: \$app_java_home is still empty. Calling test_jvm() with arg \$INSTALL4J_JAVA_HOME ('$INSTALL4J_JAVA_HOME')..."
  test_jvm "$INSTALL4J_JAVA_HOME"
fi

  if [ -z "$app_java_home" ]; then echo "search_jre step 9: \$app_java_home is still empty."
    if [ -f "$app_home/.install4j/inst_jre.cfg" ]; then echo "search_jre step 9: path '\$app_home/.install4j/inst_jre.cfg' ('$app_home/.install4j/inst_jre.cfg') exists."
      read file_jvm_home < "$app_home/.install4j/inst_jre.cfg"; echo "search_jre step 9: contents of inst_jre.cfg assigned to \$file_jvm_home. Calling test_jvm() with arg \$file_jvm_home ('$file_jvm_home').."
    test_jvm "$file_jvm_home"
      if [ -z "$app_java_home" ] && [ $tested_jvm = "false" ]; then echo "search_jre step 9: \$app_java_home is still empty and \$tested_jvm is false."
        if [ -f "$db_file" ]; then echo "search_jre step 9: attempting to silently delete \$db_file ('$db_file')..."
  rm "$db_file" 2> /dev/null
        fi; echo "search_jre step 9: calling test_jvm() with arg \$file_jvm_home ('$file_jvm_home')..."
        test_jvm "$file_jvm_home"
    fi
fi
fi

}

TAR_OPTIONS="--no-same-owner"
export TAR_OPTIONS

old_pwd=`pwd`

progname=`basename "$0"`
linkdir=`dirname "$0"`

cd "$linkdir"
prg="$progname"

while [ -h "$prg" ] ; do
  ls=`ls -ld "$prg"`
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '.*/.*' > /dev/null; then
    prg="$link"
  else
    prg="`dirname $prg`/$link"
  fi
done

prg_dir=`dirname "$prg"`
progname=`basename "$prg"`
cd "$prg_dir"
prg_dir=`pwd`
app_home=.
cd "$app_home"
app_home=`pwd`
bundled_jre_home="$app_home/jre"

if [ "__i4j_lang_restart" = "$1" ]; then
  cd "$old_pwd"
else
  cd "$prg_dir"/.

  gunzip_path=`command -v gunzip 2> /dev/null`
  if [ "$?" -ne "0" ] || [ "W$gunzip_path" = "W" ]; then
    gunzip_path=`which gunzip 2> /dev/null`
    if [ "$?" -ne "0" ]; then
      gunzip_path=""
    fi
  fi
  if [ "W$gunzip_path" = "W" ]; then
    echo "Sorry, but I could not find gunzip in path. Aborting."
    exit 1
  fi

  if [ -d "$INSTALL4J_TEMP" ]; then
     sfx_dir_name="$INSTALL4J_TEMP/${progname}.$$.dir"
  elif [ "__i4j_extract_and_exit" = "$1" ]; then
     sfx_dir_name="${progname}.test"
  else
     sfx_dir_name="${progname}.$$.dir"
  fi
  mkdir "$sfx_dir_name" > /dev/null 2>&1
  if [ ! -d "$sfx_dir_name" ]; then
    sfx_dir_name="/tmp/${progname}.$$.dir"
    mkdir "$sfx_dir_name"
    if [ ! -d "$sfx_dir_name" ]; then
      echo "Could not create dir $sfx_dir_name. Aborting."
      exit 1
    fi
  fi
  cd "$sfx_dir_name"
  if [ "$?" -ne "0" ]; then
    echo "The temporary directory could not created due to a malfunction of the cd command. Is the CDPATH variable set without a dot?"
    exit 1
  fi
  sfx_dir_name=`pwd`
  if [ "W$old_pwd" = "W$sfx_dir_name" ]; then
      echo "The temporary directory could not created due to a malfunction of basic shell commands."
      exit 1
  fi
  trap 'cd "$old_pwd"; rm -R -f "$sfx_dir_name"; exit 1' HUP INT QUIT TERM
  # tail -c 1940671 "$prg_dir/${progname}" > sfx_archive.tar.gz 2> /dev/null
  # if [ "$?" -ne "0" ]; then
  #   tail -1940671c "$prg_dir/${progname}" > sfx_archive.tar.gz 2> /dev/null
  #   if [ "$?" -ne "0" ]; then
  #     echo "tail didn't work. This could be caused by exhausted disk space. Aborting."
  #     returnCode=1
  #     cd "$old_pwd"
  #     if [ ! "W $INSTALL4J_KEEP_TEMP" = "W yes" ]; then
  #       rm -R -f "$sfx_dir_name"
  #     fi
  #     exit $returnCode
  #   fi
  # fi
  gunzip sfx_archive.tar.gz
  if [ "$?" -ne "0" ]; then
    echo ""
    echo "I am sorry, but the installer file seems to be corrupted."
    echo "If you downloaded that file please try it again. If you"
    echo "transfer that file with ftp please make sure that you are"
    echo "using binary mode."
    returnCode=1
    cd "$old_pwd"
    if [ ! "W $INSTALL4J_KEEP_TEMP" = "W yes" ]; then
      rm -R -f "$sfx_dir_name"
    fi
    exit $returnCode
  fi
  tar xf sfx_archive.tar  > /dev/null 2>&1
  if [ "$?" -ne "0" ]; then
    echo "Could not untar archive. Aborting."
    returnCode=1
    cd "$old_pwd"
    if [ ! "W $INSTALL4J_KEEP_TEMP" = "W yes" ]; then
      rm -R -f "$sfx_dir_name"
    fi
    exit $returnCode
  fi

fi
if [ "__i4j_extract_and_exit" = "$1" ]; then
  cd "$old_pwd"
  exit 0
fi
db_home=$HOME
db_file_suffix=
if [ ! -w "$db_home" ]; then
  db_home=/tmp
  db_file_suffix=_$USER
fi
db_file=$db_home/.install4j$db_file_suffix
if [ -d "$db_file" ] || ([ -f "$db_file" ] && [ ! -r "$db_file" ]) || ([ -f "$db_file" ] && [ ! -w "$db_file" ]); then
  db_file=$db_home/.install4j_jre$db_file_suffix
fi
if [ -f "$db_file" ]; then
  rm "$db_file" 2> /dev/null
fi
if [ ! "__i4j_lang_restart" = "$1" ]; then

if [ -f "$prg_dir/jre.tar.gz" ] && [ ! -f jre.tar.gz ] ; then
  cp "$prg_dir/jre.tar.gz" .
fi

echo "Checking if jre.tar.gz exists in '$pwd' and is a file..."
if [ -f jre.tar.gz ]; then echo "jre.tar.gz exists and is a file."
  echo "Unpacking JRE ..."
  gunzip jre.tar.gz
  mkdir jre
  cd jre
  tar xf ../jre.tar
  app_java_home=`pwd`
  bundled_jre_home="$app_java_home"
  cd ..; echo "After unpacking JRE, \$app_java_home is '$app_java_home' and \$bundled_jre_home is '$bundled_jre_home'.";
fi

run_unpack200 "$bundled_jre_home"
run_unpack200 "$bundled_jre_home/jre"
else
  if [ -d jre ]; then
    app_java_home=`pwd`
    app_java_home=$app_java_home/jre
  fi
fi
search_jre; echo "func search_jre executed. \$app_java_home is '$app_java_home'" # see L283
if [ -z "$app_java_home" ]; then
  echo "No suitable Java Virtual Machine could be found on your system."

  wget_path=`command -v wget 2> /dev/null`
  if [ "$?" -ne "0" ] || [ "W$wget_path" = "W" ]; then
    wget_path=`which wget 2> /dev/null`
    if [ "$?" -ne "0" ]; then
      wget_path=""
    fi
  fi
  curl_path=`command -v curl 2> /dev/null`
  if [ "$?" -ne "0" ] || [ "W$curl_path" = "W" ]; then
    curl_path=`which curl 2> /dev/null`
    if [ "$?" -ne "0" ]; then
      curl_path=""
    fi
  fi

  jre_http_url="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.1%2B12/OpenJDK17U-jre_x64_linux_hotspot_17.0.1_12.tar.gz"

  if [ -f "$wget_path" ]; then
      echo "Downloading JRE with wget ..."
      wget -O jre.tar.gz "$jre_http_url"
  elif [ -f "$curl_path" ]; then
      echo "Downloading JRE with curl ..."
      curl "$jre_http_url" -o jre.tar.gz
  else
      echo "Could not find a suitable download program."
      echo "You can download the jre from:"
      echo $jre_http_url
      echo "Rename the file to jre.tar.gz and place it next to the installer."
      returnCode=1
      cd "$old_pwd"
      if [ ! "W $INSTALL4J_KEEP_TEMP" = "W yes" ]; then
        rm -R -f "$sfx_dir_name"
      fi
      exit $returnCode
  fi

  if [ ! -f "jre.tar.gz" ]; then
      echo "Could not download JRE. Aborting."
      returnCode=1
      cd "$old_pwd"
      if [ ! "W $INSTALL4J_KEEP_TEMP" = "W yes" ]; then
        rm -R -f "$sfx_dir_name"
      fi
      exit $returnCode
  fi

if [ -f jre.tar.gz ]; then
  echo "Unpacking JRE ..."
  gunzip jre.tar.gz
  mkdir jre
  cd jre
  tar xf ../jre.tar
  app_java_home=`pwd`
  bundled_jre_home="$app_java_home"
  cd ..
fi

run_unpack200 "$bundled_jre_home"
run_unpack200 "$bundled_jre_home/jre"
fi
if [ -z "$app_java_home" ]; then
  echo "No suitable Java Virtual Machine could be found on your system."
  echo The version of the JVM must be at least 17.0.1 and at most 17.0.999.
  echo Please define INSTALL4J_JAVA_HOME to point to a suitable JVM.
  returnCode=83
  cd "$old_pwd"
  if [ ! "W $INSTALL4J_KEEP_TEMP" = "W yes" ]; then
    rm -R -f "$sfx_dir_name"
  fi
  exit $returnCode
fi



packed_files="*.jar.pack user/*.jar.pack user/*.zip.pack"
for packed_file in $packed_files
do
  unpacked_file=`expr "$packed_file" : '\(.*\)\.pack$'`
  $app_java_home/bin/unpack200 -q -r "$packed_file" "$unpacked_file" > /dev/null 2>&1
done

local_classpath=""
i4j_classpath="i4jruntime.jar:launcher0.jar"
add_class_path "$i4j_classpath"

LD_LIBRARY_PATH="$sfx_dir_name/user:$LD_LIBRARY_PATH"
DYLD_LIBRARY_PATH="$sfx_dir_name/user:$DYLD_LIBRARY_PATH"
SHLIB_PATH="$sfx_dir_name/user:$SHLIB_PATH"
LIBPATH="$sfx_dir_name/user:$LIBPATH"
LD_LIBRARYN32_PATH="$sfx_dir_name/user:$LD_LIBRARYN32_PATH"
LD_LIBRARYN64_PATH="$sfx_dir_name/user:$LD_LIBRARYN64_PATH"
export LD_LIBRARY_PATH
export DYLD_LIBRARY_PATH
export SHLIB_PATH
export LIBPATH
export LD_LIBRARYN32_PATH
export LD_LIBRARYN64_PATH

for param in $@; do
  if [ `echo "W$param" | cut -c -3` = "W-J" ]; then
    INSTALL4J_ADD_VM_PARAMS="$INSTALL4J_ADD_VM_PARAMS `echo "$param" | cut -c 3-`"
  fi
done


has_space_options=false
if [ "W$vmov_1" = "W" ]; then
  vmov_1="-Di4jv=0"
else
  has_space_options=true
fi
if [ "W$vmov_2" = "W" ]; then
  vmov_2="-Di4jv=0"
else
  has_space_options=true
fi
if [ "W$vmov_3" = "W" ]; then
  vmov_3="-Di4jv=0"
else
  has_space_options=true
fi
if [ "W$vmov_4" = "W" ]; then
  vmov_4="-Di4jv=0"
else
  has_space_options=true
fi
if [ "W$vmov_5" = "W" ]; then
  vmov_5="-Di4jv=0"
else
  has_space_options=true
fi
echo "Starting Installer ..."

return_code=0
umask 0022
if [ "$has_space_options" = "true" ]; then echo "$app_java_home"
$INSTALL4J_JAVA_PREFIX "$app_java_home/bin/java" -Dexe4j.moduleName="$prg_dir/sfx_archive.tar.gz" -Dexe4j.totalDataLength=1985397 -Dinstall4j.cwd="$old_pwd" "$vmov_1" "$vmov_2" "$vmov_3" "$vmov_4" "$vmov_5" $INSTALL4J_ADD_VM_PARAMS -classpath "$local_classpath" install4j.Installer465309369  "$@"
return_code=$?
else echo "$app_java_home"
$INSTALL4J_JAVA_PREFIX "$app_java_home/bin/java" -Dexe4j.moduleName="$prg_dir/sfx_archive.tar.gz" -Dexe4j.totalDataLength=1985397 -Dinstall4j.cwd="$old_pwd" $INSTALL4J_ADD_VM_PARAMS -classpath "$local_classpath" install4j.Installer465309369  "$@"
return_code=$?
fi


returnCode=$return_code
cd "$old_pwd"
if [ ! "W $INSTALL4J_KEEP_TEMP" = "W yes" ]; then
  rm -R -f "$sfx_dir_name"
fi
exit $returnCode
