#!/bin/bash

script_name=`basename $0`
script_dir=`dirname $0`
version="???"

if [ -f "$script_dir/VERSION" ] ; then
   version=`cat $script_dir/VERSION`
fi

gpu="0"

function usage()
{
    echo "usage: $script_name [-h]
                      predictdir

              Version: $version

              Runs caffe prediction on CDeep3M trained model using
              predict.config file to obtain location of trained
              model and image data

positional arguments:
  predictdir           Predict directory generated by
                       runprediction.sh

optional arguments:
  -h, --help           show this help message and exit

    " 1>&2;
   exit 1;
}

TEMP=`getopt -o h --long "help" -n '$0' -- "$@"`
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -h ) usage ;;
        --help ) usage ;;
        --) shift ; break ;;
    esac
done

if [ $# -ne 1 ] ; then
  usage
fi

out_dir=$1

echo ""

predict_config="$out_dir/predict.config"

if [ ! -s "$predict_config" ] ; then
  echo "ERROR no $predict_config file found"
  exit 2
fi

trained_model_dir=`egrep "^ *trainedmodeldir *=" "$predict_config" | sed "s/^.*=//" | sed "s/^ *//"`

if [ -z "$trained_model_dir" ] ; then
  echo "ERROR unable to extract trainedmodeldir from $predict_config"
  exit 3
fi

img_dir=`egrep "^ *imagedir *=" "$predict_config" | sed "s/^.*=//" | sed "s/^ *//"`

if [ -z "$img_dir" ] ; then
  echo "ERROR unable to extract imagedir from $predict_config"
  exit 4
fi


model_list=`egrep "^ *models *=" "$predict_config" | sed "s/^.*=//" | sed "s/^ *//"`

if [ -z "$model_list" ] ; then
  echo "ERROR unable to extract models from $predict_config"
  exit 5
fi

aug_speed=`egrep "^ *augspeed *=" "$predict_config" | sed "s/^.*=//" | sed "s/^ *//"`

if [ -z "$aug_speed" ] ; then
  echo "ERROR unable to extract augspeed from $predict_config"
  exit 6
fi


echo "Running Prediction"
echo ""

echo "Trained Model Dir: $trained_model_dir"
echo "Image Dir: $img_dir"
echo "Models: $model_list"
echo "Speed: $aug_speed"
echo ""

package_proc_info="$out_dir/augimages/package_processing_info.txt"

if [ ! -s "$package_proc_info" ] ; then
  echo "ERROR $package_proc_info not found"
  exit 7
fi

cp "$out_dir/augimages/de_augmentation_info.mat" "$out_dir/."

if [ $? != 0 ] ; then
  echo "ERROR unable to copy $out_dir/augimages/de_augmentation_info.mat to $out_dir"
  exit 8
fi

cp "$out_dir/augimages/package_processing_info.txt" "$out_dir/."

if [ $? != 0 ] ; then
  echo "ERROR unable to copy $out_dir/augimages/package_processing_info.txt to $out_dir"
  exit 9
fi

num_pkgs=`head -n 3 $package_proc_info | tail -n 1`
num_zstacks=`tail -n 1 $package_proc_info`
let tot_pkgs=$num_pkgs*$num_zstacks
for model_name in `echo "$model_list" | sed "s/,/ /g"` ; do
  
  echo "Running $model_name predict $tot_pkgs package(s) to process"
  let cntr=1
  for CUR_PKG in `seq -w 001 $num_pkgs` ; do
    for CUR_Z in `seq -w 01 $num_zstacks` ; do
      pkg_name="Pkg${CUR_PKG}_Z${CUR_Z}"
      Z="$out_dir/augimages/$model_name/$pkg_name"
      out_pkg="$out_dir/$model_name/$pkg_name"
      if [ -f "$out_pkg/DONE" ] ; then
        echo "  Found $out_pkg/DONE. Prediction completed. Skipping..."
        continue
      fi
      echo -n "  Processing $pkg_name $cntr of $tot_pkgs "
      outfile="$out_pkg/out.log"
      PreprocessPackage.m "$img_dir" "$out_dir/augimages" $CUR_PKG $CUR_Z $model_name $aug_speed
      ecode=$?
      if [ $ecode != 0 ] ; then
        echo "ERROR, a non-zero exit code ($ecode) was received from: PreprocessPackage.m \"$img_dir\" \"$out_pkg\" $CUR_PKG $CUR_Z $model_name $aug_speed"
        exit 10
      fi

      /usr/bin/time -p caffepredict.sh --gpu $gpu "$trained_model_dir/$model_name/trainedmodel" "$Z" "$out_pkg"
      ecode=$?
      if [ $ecode != 0 ] ; then
        echo "ERROR, a non-zero exit code ($ecode) was received from: /usr/bin/time -p caffepredict.sh --gpu $gpu \"$trained_model_dir/$model_name/trainedmodel\" \"$Z\" \"$out_pkg\""
        if [ -f "$outfile" ] ; then
          echo "Here is last 10 lines of $outfile:"
          echo ""
          tail $outfile
        fi
        exit 11
      fi
      echo "Prediction completed: `date +%s`" > "$out_pkg/DONE"
      let cntr+=1
    done
  done
  if [ -f "$out_dir/$model_name/DONE" ] ; then
    echo "Found $out_dir/$model_name/DONE. Merge completed. Skipping..."
    continue
  fi
  echo ""
  echo "Running Merge_LargeData.m $out_dir/$model_name"
  merge_log="$out_dir/$model_name/merge.log"
  Merge_LargeData.m "$out_dir/$model_name" >> "$merge_log" 2>&1
  ecode=$?
  if [ $ecode != 0 ] ; then
    echo "ERROR, a non-zero exit code ($ecode) from running Merge_LargeData.m"
    exit 12
  fi
  echo "Merge completed: `date +%s`" > "$out_dir/$model_name/DONE"
done

echo ""
echo "Prediction has completed. Have a nice day!"
echo ""
