#!/bin/bash

set -e

function log() {
   echo -n `date -u '+%Y-%m-%d %H:%M:%S'`' '
   echo "$*"
}
 
SCRATCH=/scratch/wrf
SHARE=/share/wrf
GFS_DIR=$SCRATCH/gfs/
WPS_HOME=$SHARE/prg/WPS
WRF_HOME=$SHARE/prg/WRF
DEPS=$SHARE/prg/deps
RESULT_DIR=$SCRATCH/workdir/results
WPS_WORKDIR=$SCRATCH/workdir/wps
WRF_WORKDIR=$SCRATCH/workdir/wrf

PATH=$DEPS/bin:$PATH
export LD_LIBRARY_PATH=$DEPS/lib:$LD_LIBRARY_PATH

#
DT_BEG=$(date -u +"%Y-%m-%d_00:00:00")
DT_BEG_YEAR=${DT_BEG:0:4}
DT_BEG_MONTH=${DT_BEG:5:2}
DT_BEG_DAY=${DT_BEG:8:2}
#
DT_END=$(date -u -d "+ 3 days" +"%Y-%m-%d_00:00:00")
DT_END_YEAR=${DT_END:0:4}
DT_END_MONTH=${DT_END:5:2}
DT_END_DAY=${DT_END:8:2}
#
FILE_NAME=sudan-d01-${DT_BEG}UTC.nc
LOCAL_PATH=$RESULT_DIR/$FILE_NAME

DT_FORECAST=$DT_BEG_YEAR$DT_BEG_MONTH$DT_BEG_DAY

export LD_LIBRARY_PATH=$SHARE/lib:$LD_LIBRARY_PATH
export PATH=$SHARE/bin:$PATH
ulimit -s unlimited

<< EOC
log Simulation starting. 
log '  ' \$DT_FORECAST=$DT_FORECAST

log Build WPS workdir

rm -rf $WPS_WORKDIR
rm -rf $WRF_WORKDIR
rm -rf $GFS_DIR
mkdir -p $WPS_WORKDIR
mkdir -p $WRF_WORKDIR
mkdir -p $GFS_DIR

NML_WPS=$WPS_WORKDIR/namelist.wps
NML_WRF=$WPS_WORKDIR/namelist.input
cp $SHARE/cfg/namelist.wps $NML_WPS
cp $SHARE/cfg/namelist.input $NML_WRF

sed -i 's@$dateBeg@'"$DT_BEG"'@g' $NML_WPS
sed -i 's@$dateEnd@'"$DT_END"'@g' $NML_WPS
sed -i 's@$dateBegY@'"$DT_BEG_YEAR"'@g' $NML_WRF
sed -i 's@$dateBegM@'"$DT_BEG_MONTH"'@g' $NML_WRF
sed -i 's@$dateBegD@'"$DT_BEG_DAY"'@g' $NML_WRF
sed -i 's@$dateEndY@'"$DT_END_YEAR"'@g' $NML_WRF
sed -i 's@$dateEndM@'"$DT_END_MONTH"'@g' $NML_WRF
sed -i 's@$dateEndD@'"$DT_END_DAY"'@g' $NML_WRF

log Download GFS dataset. Log file: \$SCRATCH/workdir/wps/gfs.log
$SHARE/bin/gfsdn -c $SHARE/cfg/gfs.toml -o $SCRATCH/gfs sudan 72 ${DT_FORECAST}00 > $SCRATCH/workdir/wps/gfs.log 2>&1 &
#wait; exit
cd $WPS_WORKDIR

ln -s $WPS_HOME/*.exe .
ln -s $WPS_HOME/util/avg_tsfc.exe .
ln -s $WPS_HOME/ungrib/Variable_Tables/Vtable.GFS Vtable
ln -s $WRF_HOME/run/real.exe .

log Run geogrid. Log file: \$SCRATCH/workdir/wps/geogrid.log
mpiexec -n 36 ./geogrid.exe > geogrid.log 2>&1 &

wait

$WPS_HOME/link_grib.csh $GFS_DIR/$DT_BEG_YEAR/$DT_BEG_MONTH/$DT_BEG_DAY/0000/sudan/*

log Run ungrib. Log file: \$SCRATCH/workdir/wps/ungrib.log
./ungrib.exe > ungrib.log 2>&1

log Run avg_tsfc. Log file: \$SCRATCH/workdir/wps/avg_tsfc.log
./avg_tsfc.exe > avg_tsfc.log 2>&1

log Run metgrid. Log file: \$SCRATCH/workdir/wps/metgrid.log
mpiexec -n 24 ./metgrid.exe > metgrid.log 2>&1 

log Run real. Log file: \$SCRATCH/workdir/wps/real.log
mpiexec -n 24 ./real.exe > real.log 2>&1  

log Build WRF workdir. 

# UPLOAD NAMELIST E CONDITIONS
cp wrf[bi]* namelist.input $WRF_WORKDIR

cd $WRF_WORKDIR

ln -s $WRF_HOME/main/wrf.exe .
ln -s $WRF_HOME/run/LANDUSE.TBL .
ln -s $WRF_HOME/run/ozone_plev.formatted .
ln -s $WRF_HOME/run/ozone_lat.formatted .
ln -s $WRF_HOME/run/ozone.formatted .
ln -s $WRF_HOME/run/RRTMG_LW_DATA .
ln -s $WRF_HOME/run/RRTMG_SW_DATA .
ln -s $WRF_HOME/run/VEGPARM.TBL .
ln -s $WRF_HOME/run/SOILPARM.TBL .
ln -s $WRF_HOME/run/GENPARM.TBL .

log Run WRF. Log file: \$SCRATCH/workdir/wrf/wrf.log
nproc
mpiexec -n 64 ./wrf.exe > wrf.log 2>&1  

cd $WRF_WORKDIR

EOC
function cdorun() {
   set +e
   err=1
   count=1
   while [ $err -ne 0 ] && [ $count -le 5 ]; do
      echo cdo $@
      cdo $@
      err=$?
      echo $(( count++ ))
   done
   set -e
}


RH_EXPR="RH2=100*(PSFC*Q2/0.622)/(611.2*exp(17.67*(T2-273.15)/((T2-273.15)+243.5)))"
RAINSUM_EXPR="RAINSUM=RAINNC+RAINC"

rm -rf $RESULT_DIR
mkdir -p $RESULT_DIR

log Run Postprocess. Log file: \$SCRATCH/workdir/wrf/postprocess.log

log Fix date time
for f in $WRF_WORKDIR/auxhist23_d01_*; do
   date=$(basename $f | cut -c 15-24)
   time=$(basename $f | cut -c 26-34)
   log Fixing time for $(basename $f)
   cdorun -b F64 -O settaxis,$date,$time $f $(basename ${f}).fixdate >> postprocess.log 2>&1
done

log Merge hourly files into a single one
cdorun -O -v mergetime *.fixdate sudan-dtfrm.nc >> postprocess.log 2>&1
cdorun -O -setreftime,'2000-01-01','00:00:00' sudan-dtfrm.nc sudan.nc >> postprocess.log 2>&1

log Remove wrong variables
ncks -O -x -v P_PL,C1H,C2H,C3H,C4H,C1F,C2F,C3F,C4F sudan.nc clean-sudan.nc >> postprocess.log 2>&1

log Regridding
cdorun -O remapbil,$SHARE/cfg/cdo_wrfsudan_d01_grid.txt clean-sudan.nc rg-sudan.nc >> postprocess.log 2>&1

log Calculating RH_EXPR
cdorun -O -setrtoc,100,1.e99,100 -setunit,"%" -expr,$RH_EXPR rg-sudan.nc rh-sudan.nc >> postprocess.log 2>&1
cdorun -O -expr,$RH_EXPR rg-sudan.nc rh-sudan.nc >> postprocess.log 2>&1

log Calculating RAINSUM_EXPR
cdorun -O -expr,$RAINSUM_EXPR rg-sudan.nc rainsum-sudan.nc >> postprocess.log 2>&1

log Merging new variables with main file
cdorun -O -v -f nc4c -z zip9 merge rg-sudan.nc rainsum-sudan.nc rh-sudan.nc $RESULT_DIR/sudan-d01-${DT_BEG}UTC.nc >> postprocess.log 2>&1

log Uploading to Dewetra

PROXYCOMMAND="-o ProxyCommand='ssh -o StrictHostKeyChecking=no -i /share/wrf/cfg/id_rsa.wrfprod -W %h:%p wrfprod@130.251.104.213'"
SSHKEY='-i $SHARE/cfg/del-dewetra'
REMOTE_SERVER=wrfprod@130.251.104.19
REMOTE_BASEDIR=/share/archivio/experience/data/MeteoModels/WRF_SUDAN
REMOTE_PATH=$REMOTE_BASEDIR/$DT_BEG_YEAR/$DT_BEG_MONTH/$DT_BEG_DAY/0000

eval ssh $PROXYCOMMAND $SSHKEY -o StrictHostKeyChecking=no $REMOTE_SERVER mkdir -p $REMOTE_PATH 
eval scp $PROXYCOMMAND $SSHKEY -o StrictHostKeyChecking=no $LOCAL_PATH $REMOTE_SERVER:$REMOTE_PATH/$FILE_NAME.tmp 
eval ssh $PROXYCOMMAND $SSHKEY -o StrictHostKeyChecking=no $REMOTE_SERVER mv $REMOTE_PATH/$FILE_NAME.tmp $REMOTE_PATH/$FILE_NAME 



log Done
