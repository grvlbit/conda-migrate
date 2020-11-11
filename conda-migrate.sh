#!/bin/bash
# conda-migrate.sh
#
# a simple bash script that helps you to migrate your anaconda environment
# from one path to another and takes care of all path conversions in your
# environments
# 
# Syntax: ./conda-migrate.sh current_path new_path 
#
# Migrate conda from one directory to another.
# This involves the following steps:
# (1) fix the prefix of a previous attempt to move anaconda install 
# 2)  install basic miniconda installation into new directory
# 3)  export explicit list of packages for all environments in old conda directory
# 4)  install all environments from step 2 into new directory
#
# Authors: Matt Huska, 2018
#          Terry Jones, 2018
#          Gunnar Jansen, 2020
#
# forked from matthuska/conda-move
# 
# Changelog: 
#  * November 2020: Added options to fix prefix in botched conda installations,
#                   renamed variables, added additional checks and warnings
#                   throughout the script.
#                   Extended script for base environment in extra step.

set -Eeuo pipefail 

old_conda_dir=$(echo $1 | sed 's:/*$::')
new_conda_dir=$(echo $2 | sed 's:/*$::')

fix_prefix=0

shift 2
while (( $# > 0 )); do
  echo $1
  case $1 in
    --fix-prefix) fix_prefix=1            
    ;;
    *) break
  esac
  shift
done

escaped_old_conda_dir=$(echo $old_conda_dir | sed 's_/_\\/_g')
escaped_new_conda_dir=$(echo $new_conda_dir | sed 's_/_\\/_g')

if [[ -f "$HOME/.bashrc" && -f "$HOME/.bash_profile" ]]; then
  echo "It looks like you're using a non standard bash setup."
  echo "Sorry, but this script won't work for you. Aborting."
  exit 3;
fi

# Step 1. Check if fix_prefix option is set. If yes, proceed
#         to change the prefix in a moved conda install to the
#         correct path to restore some functionality.

if [ $fix_prefix == 1 ]; then
  while true; do
    echo "-----------------------------------------------"
    echo "WARNING: This is potentially dangerous!"
    echo "         Only do this if you have made a backup"
    echo "         of your conda directory."
    echo "-----------------------------------------------"
    read -p "Do you really wish to continue [Y/N]?" yn
    case $yn in
      [Yy]* ) break;;
      [Nn]* ) exit;;
      * ) echo "Please answer yes or no.";;
    esac
  done

  # Step 1.1. Change the path in the conda shell configuration file
  #         "$old_path/etc/profile.d/conda.sh" -> "$new_path/etc/profile.d/conda.sh"
  sed -i "s/$escaped_old_conda_dir/$escaped_new_conda_dir/g" "$new_conda_dir/etc/profile.d/conda.sh" ; 
  
  # Step 1.2. The scripts in conda environments have hard-coded 
  #         interpreter paths in their first lines. 
  #         Fix them with new path.
  #######################################
  # Replace path in all files in specified directory
  # Globals:
  #   escaped_old_path
  #   escaped_new_path
  # Arguments:
  #   Folder to search
  # Outputs:
  #   None
  #######################################
  function replace()
  {
    current="$PWD"
    cd "$1"
    for x in ./*; do 
      file "$x" | grep text && sed -i "s/$escaped_old_conda_dir/$escaped_new_conda_dir/g" "$x" ; 
    done
    cd "$current"
  }

  # Step 1.3. 
  cd "$new_conda_dir"

  # Step 1.4. Change the interpreter path in conda base environment
  replace bin

  # Step 1.5. Change the interpreter path in other conda environments
  for x in envs/*; do
    replace "$x";
  done

  # Step 1.6. Change the path in the user bashrc / bash_profile
  if [[ -f "$HOME/.bashrc" ]]; then
    sed -i "s/$escaped_old_conda_dir/$escaped_new_conda_dir/g" "$HOME/.bashrc" ; 
  elif [[ -f "$HOME/.bash_profile" ]]; then
    sed -i "s/$escaped_old_conda_dir/$escaped_new_conda_dir/g" "$HOME/.bash_profile" ; 
  else
    echo "Remember to manually update the PATH variable in your shell's start-up file to include new conda directory: $new_conda_dir"
  fi
  
  # Step 1.7. Cleanup
  echo "----------------------------------------------------------------------------------"
  echo "Prefix fix successful. Please execute 'source ~/.bashrc' to finalize the fix."
  echo "You can run conda-migrate.sh again to properly migrate your environments now!"
  echo "----------------------------------------------------------------------------------"

  exit 0;
fi

# Step 2. Confirm user inputs
if ! [ -x "$(command -v conda)" ]; then
  echo "No conda installation was found. Aborting." >&2
  exit 1;
fi
if [ ! -d "$old_conda_dir" ]; then
  echo "Old conda dir $old_conda_dir does not exist! Aborting." >&2
  exit 1;
fi

conda_version=$(conda --version)
echo "A $conda_version installation was found."
echo ""
echo "The following environments will be migrated:"
echo "$(conda info --envs | tail -n +3)"
echo ""
echo "Current conda path: $old_conda_dir"
echo "New conda path: $new_conda_dir"
echo ""

while true; do
  read -p "Do you wish to continue [Y/N]?" yn
  case $yn in
    [Yy]* ) break;;
    [Nn]* ) exit;;
    * ) echo "Please answer yes or no.";;
  esac
done

tmp_dir=$(mktemp -d)
# Make sure that worked, because we are going to use a trap to call
# 'rm -r' on the directory. 
if [ -d $tmp_dir ]; then
  trap "rm -r $tmp_dir" 0 1 2 3 15
else
  echo "mktemp failed to create a temporary directory!" >&2
  exit 2
fi

echo "-----------------------------------------------------------"
echo "Step 2) Fresh install of miniconda to target dir ($new_conda_dir)"
echo "-----------------------------------------------------------"

if [ -d "$new_conda_dir" ]; then
  echo "Found existing conda installation in $new_conda_dir, skipping conda installation."
else
  wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O Miniconda3-latest-Linux-x86_64.sh
  bash Miniconda3-latest-Linux-x86_64.sh -b -f -p "${new_conda_dir}"
  
  if [ ! -d "$new_conda_dir" ]
  then
    echo "Conda install failed to create new conda dir $new_conda_dir!" >&2
    exit 3
  fi
fi

dot_conda_dir=$HOME/.conda
if [ -d "$dot_conda_dir" ]; then
  echo "Found existing $dot_conda_dir, will rename this to $dot_conda_dir.bak.  Remove it after checking that everything works."
  mv "$dot_conda_dir" "$dot_conda_dir.bak"
fi

echo "-----------------------------------------------------------"
echo "Step 3) export explicit package lists for all environments in old conda installation ($old_conda_dir)"
echo "-----------------------------------------------------------"

conda_envs=$(cd $old_conda_dir/envs && ls -d *)
conda_envs+=("base")

cd $tmp_dir
move_dir=$tmp_dir/conda-move-envs

mkdir $move_dir

for env in ${conda_envs[@]}; do
  echo "Exporting environment: $env"
  
  yml="$move_dir/$env.yml"
  txt="$move_dir/$env.txt"
  
  CONDA_ENVS_PATH=$old_conda_dir/envs/ conda list --explicit --name "$env" > "$txt"
  CONDA_ENVS_PATH=$old_conda_dir/envs/ conda env export --no-builds --name "$env" > "$yml"
done

# Store a backup of exported environments in an archive in users $HOME
conda_backup_dir=$HOME/.conda_backups
if [ ! -d "$conda_backup_dir" ]; then
  mkdir -p $conda_backup_dir
  echo "Create anaconda env backup directory $conda_backup_dir"
fi

if [ ! -d "$conda_backup_dir" ]; then
  echo "Failed to create new conda env backup dir $conda_backup_dir!" >&2
  exit 3;
else
  today=$(date +"%Y-%m-%d")
  conda_env_backup="${conda_backup_dir}/conda_envs_${today}.tar.gz"
  tar -czf ${conda_backup_dir}/conda_envs_${today}.tar.gz .

fi

echo "-----------------------------------------------------------"
echo "Step 4) import environments into new conda installation ($new_conda_dir)"
echo "-----------------------------------------------------------"

failed_envs=$move_dir/failed-envs.txt
touch $failed_envs

for env in ${conda_envs[@]}; do
  echo "Importing environment: $env"
  
  yml="$move_dir/$env.yml"
  txt="$move_dir/$env.txt"
  
  if [ $env == "base" ]; then
    set -x
    conda install --prefix "$new_conda_dir" --file "$txt" || \
    conda env create --prefix "$new_conda_dir" --file "$yml" --force || \
    echo "$env" >> "$failed_envs"
    set +x
  elif [ ! -d "$new_conda_dir/envs/$env" ]; then
    # First try to recreate the exact environment. If that fails, create an
    # environment with the same packages but possibly newer packages.
    set -x
    conda create --prefix "$new_conda_dir/envs/$env" --file "$txt" || \
    conda env create --prefix "$new_conda_dir/envs/$env" --file "$yml" || \
    echo "$env" >> "$failed_envs"
    set +x
  fi
done
if (( $? != 0 )); then
  echo "Fatal error during conda migration. Aborting."
fi

# Step 6. Change the path in the user bashrc / bash_profile
if [[ -f "$HOME/.bashrc" ]]; then
  sed -i "s/$escaped_old_conda_dir/$escaped_new_conda_dir/g" "$HOME/.bashrc" ; 
elif [[ -f "$HOME/.bash_profile" ]]; then
  sed -i "s/$escaped_old_conda_dir/$escaped_new_conda_dir/g" "$HOME/.bash_profile" ; 
fi

# Step 7. Cleanup
if (( $? == 0 )); then
  echo "----------------------------------------------------------------------------------"
  echo "Migration finished. Please execute 'source ~/.bashrc' to finalize the migration."
  if [ -s "$failed_envs" ]
  then
    echo "Beware: There were environments that were not properly migrated."
    echo "        You might need to restore them manually from backup"
    echo "        (e.g. ${conda_env_backup})"
    echo "Failed envs:"
    cat "$failed_envs"
  fi
  echo "Lastly, please test your new conda installation."
  echo "Only then you should remove the old one at: $old_conda_dir"
  echo "----------------------------------------------------------------------------------"
fi 
