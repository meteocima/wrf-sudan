#!/bin/bash
set -e

fail_usage() {
  ERROR=$1
  echo "usage: RUNDATE (format YYYYMMDD) RUNHOUR (format HH)"
  echo $ERROR
  exit 1

}

if [[ $# != 2 ]]; then
  fail_usage "ERROR: RUNDATE and RUNHOUR arguments required"
fi

RUNDATE=$1
RUNHOUR=$2

if [[ ${#RUNDATE} != 8 ]]; then
  fail_usage "ERROR: invalid format for RUNDATE argument: \`$RUNDATE\`. Expected format is YYYYMMDD"
fi

set +e 
date -d "${RUNDATE:0:4}-${RUNDATE:4:2}-${RUNDATE:6:2}" > /dev/null 2>&1
if [ $? != 0 ]; then
  fail_usage "ERROR: invalid format for RUNDATE argument: \`$RUNDATE\`. Expected format is YYYYMMDD"
fi
set -e

re='^[0-9][0-9]$'

if ! [[ $RUNHOUR =~ $re ]] ; then
   fail_usage "ERROR: invalid format for RUNHOUR argument: \`$RUNHOUR\`. Expected format is HH"
fi

ROOT_DIR=/data/safe/nowcasting

if [[ $RUNHOUR==3 || $RUNHOUR==9 || $RUNHOUR==15 || $RUNHOUR==21 ]]; then
	DELTA_WPS_H=$(( $RUNHOUR + -9 ))
else
	DELTA_WPS_H=$(( $RUNHOUR + -6 ))
fi

WPS_DATE=`date '+%C%y-%m-%d %H:00' -d "$RUNDATE+$DELTA_WPS_H hours"`
WPS_INSTANT=`date '+_%d_%H' -d "$WPS_DATE"`
SRC_DIR=$ROOT_DIR/workdir/$RUNDATE/$RUNDATE$RUNHOUR$WPS_INSTANT
echo SRC DIR $SRC_DIR
RH_EXPR="RH2=100*(PSFC*Q2/0.622)/(611.2*exp(17.67*(T2-273.15)/((T2-273.15)+243.5)))"
RAINSUM_EXPR="RAINSUM=RAINNC+RAINC"
REGRID_DIR=$ROOT_DIR/workdir/regrids/

export LD_LIBRARY_PATH=/data/safe/cdo-1-7-2/out/lib:$LD_LIBRARY_PATH
export PATH=/data/safe/cdo-1-7-2/out/bin:$PATH


get-dest-name() {
  echo ../dewetra/nowcasting-d03-${RUNDATE}_${HOUR}UTC.nc
}

do_upload() {
  HOUR=$1
  REMOTE_SERVER=wrfprod@130.251.104.19
  REMOTE_BASEDIR=/share/archivio/experience/data/MeteoModels/NOWCASTING_WRF
  REMOTE_PATH=$REMOTE_BASEDIR/${RUNDATE:0:4}/${RUNDATE:4:2}/${RUNDATE:6:2}/${HOUR}00
  ssh -i ~/.ssh/id_rsa.antonio $REMOTE_SERVER mkdir -p $REMOTE_PATH
  LOCAL_PATH=`HOUR=$HOUR get-dest-name`
  FILE_NAME=`basename $LOCAL_PATH`
  echo Uploading to Dewetra
  scp -i ~/.ssh/id_rsa.antonio $LOCAL_PATH $REMOTE_SERVER:$REMOTE_PATH/$FILE_NAME.tmp
  ssh -i ~/.ssh/id_rsa.antonio $REMOTE_SERVER mv $REMOTE_PATH/$FILE_NAME.tmp $REMOTE_PATH/$FILE_NAME
}

do_regrid() {
  SRC_DIR=$1
  export HOUR=$2
  DEST_NAME=`get-dest-name`
 # echo $SRC_DIR -- $DEST_NAME

  rm -rf $REGRID_DIR
  mkdir -p $REGRID_DIR
  cd $REGRID_DIR
  
  echo Fix date time 
  for f in $SRC_DIR/wrf/auxhist23_d03_*; do
    date=`basename $f | cut -c 15-24`
    time=`basename $f | cut -c 26-34`
    echo Fixing time for `basename $f`
    cdo -b F64 -O settaxis,$date,$time $f `basename ${f}`.fixdate 
    #cdo -O settaxis,$date,$time $f `basename ${f}`.fixdate 
  done

  echo Merge hourly files into a single one
  cdo -O -v mergetime *.fixdate nowcasting-dtfrm.nc 
  cdo -O -setreftime,'2000-01-01','00:00:00' nowcasting-dtfrm.nc nowcasting.nc

  echo Remove wrong variables 
  ncks -O -x -v P_PL,C1H,C2H,C3H,C4H,C1F,C2F,C3F,C4F,GHT_PL,Q_PL,RH_PL,S_PL,TD_PL,T_PL,U_PL,V_PL,EMISS,GLW,GRDFLX,HFX,UST,ZNT nowcasting.nc clean-nowcasting.nc

  echo Regridding
  cdo -O remapbil,/data/safe/wrfita/bin/cdo_wrfita-d03_grid_25.txt clean-nowcasting.nc rg-nowcasting.nc

  echo Calculating RH_EXPR
  cdo -O -setrtoc,100,1.e99,100 -setunit,"%" -expr,$RH_EXPR rg-nowcasting.nc rh-nowcasting.nc

  echo Calculating RAINSUM_EXPR
  cdo -O -setrtoc,100,1.e99,100 -setunit,"%" -expr,$RAINSUM_EXPR rg-nowcasting.nc rainsum-nowcasting.nc

  echo Merging new variables with main file
  cdo -O -v -f nc4c -z zip9 merge rg-nowcasting.nc rainsum-nowcasting.nc rh-nowcasting.nc $DEST_NAME

  echo Done
}

do_regrid $SRC_DIR $RUNHOUR
do_upload $RUNHOUR

