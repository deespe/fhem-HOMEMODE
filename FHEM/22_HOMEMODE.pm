#####################################################################################
# $Id: 22_HOMEMODE.pm 26813 2022-12-07 21:19:57Z DeeSPe $
#
# Usage
#
# define <name> HOMEMODE [RESIDENTS-MASTER-DEVICE]
#
#####################################################################################

package FHEM::Automation::HOMEMODE;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use List::Util qw(uniq);
use HttpUtils;
use FHEM::Meta;
use Data::Dumper;
use GPUtils qw(GP_Import);


my $HOMEMODE_version = '2.0.0';
my $HOMEMODE_Daytimes = '05:00|morning 10:00|day 14:00|afternoon 18:00|evening 23:00|night';
my $HOMEMODE_Seasons = '03.01|spring 06.01|summer 09.01|autumn 12.01|winter';
my $HOMEMODE_UserModes = 'gotosleep,awoken,asleep';
my $HOMEMODE_UserModesAll = $HOMEMODE_UserModes.',home,absent,gone';
my $HOMEMODE_AlarmModes = 'disarm,confirm,armhome,armnight,armaway';
my $HOMEMODE_Locations = 'arrival,home,bed,underway,wayhome';
my $langDE;
my $ver = $HOMEMODE_version;
$ver =~ s/\.\d{1,2}$//x;

BEGIN {
  GP_Import(
    qw(
      AnalyzeCommandChain
      AttrNum
      AttrVal
      Calendar_GetEvents
      CommandAttr
      CommandDefine
      CommandDelete
      CommandDeleteAttr
      CommandDeleteReading
      CommandSet
      CommandTrigger
      Debug
      DoTrigger
      FileRead
      HttpUtils_NonblockingGet
      InternalVal
      InternalTimer
      IsDisabled
      Log3
      ReadingsAge
      ReadingsNum
      ReadingsVal
      RemoveInternalTimer
      ReplaceEventMap
      SemicolonEscape
      FW_detail
      FW_hidden
      FW_select
      FW_textfieldv
      data
      attr
      defs
      deviceEvents
      devspec2array
      decode_base64
      encode_base64
      filter_true
      gettimeofday
      init_done
      modules
      init_done
      makeReadingName
      perlSyntaxCheck
      readingFnAttributes
      readingsBeginUpdate
      readingsBulkUpdate
      readingsBulkUpdateIfChanged
      readingsEndUpdate
      readingsSingleUpdate
    )
  );
}

sub ::HOMEMODE_Initialize { goto &Initialize }

sub Initialize
{
  my ($hash) = @_;
  $hash->{AttrFn}       = \&Attr;
  $hash->{DefFn}        = \&Define;
  $hash->{NotifyFn}     = \&Notify;
  $hash->{GetFn}        = \&Get;
  $hash->{SetFn}        = \&Set;
  $hash->{UndefFn}      = \&Undef;
  $hash->{FW_detailFn}  = \&Details;
  $hash->{AttrList}     = 'disable:1,0 disabledForIntervals Home.* '.$readingFnAttributes;
  $hash->{NotifyOrderPrefix} = '51-';
  $hash->{FW_deviceOverview} = 1;
  $hash->{FW_addDetailToSummary} = 1;
  $data{FWEXT}{HOMEMODE}{SCRIPT} = 'homemode.js';
  return FHEM::Meta::InitMod(__FILE__,$hash);
}

sub Define
{
  my ($hash,$def) = @_;
  my @args = split ' ',$def;
  my ($name,$type,$resdev) = @args;
  Log3 $name,4,"$name: Define called";
  $langDE = AttrVal('global','language','EN') eq 'DE' || AttrVal($name,'HomeLanguage','EN' eq 'DE') ? 1 : 0;
  my $text;
  if (@args < 2 || @args > 3)
  {
    $text = $langDE?
      'Benutzung: define <name> HOMEMODE [RESIDENTS-MASTER-GERAET]':
      'Usage: define <name> HOMEMODE [RESIDENTS-MASTER-DEVICE]';
    return $text;
  }
  RemoveInternalTimer($hash);
  $hash->{NOTIFYDEV} = 'global';
  if ($init_done && !defined $hash->{OLDDEF})
  {
    $attr{$name}{devStateIcon}  = 'absent:user_away:dnd+on\n'.
                                  'gone:user_ext_away:dnd+on\n'.
                                  'dnd:audio_volume_mute:dnd+off\n'.
                                  'gotosleep:scene_sleeping:dnd+on\n'.
                                  'asleep:scene_sleeping_alternat:dnd+on\n'.
                                  'awoken:weather_sunrise:dnd+on\n'.
                                  'home:status_available:dnd+on\n'.
                                  'morning:weather_sunrise:dnd+on\n'.
                                  'day:weather_sun:dnd+on\n'.
                                  'afternoon:weather_summer:dnd+on\n'.
                                  'evening:weather_sunset:dnd+on\n'.
                                  'night:weather_moon_phases_2:dnd+on';
    $attr{$name}{icon}          = 'floor';
    $attr{$name}{room}          = 'HOMEMODE';
    $attr{$name}{webCmd}        = 'modeAlarm';
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,'dnd','off') if (!defined ReadingsVal($name,'dnd',undef));
    readingsBulkUpdate($hash,'anyoneElseAtHome','off') if (!defined ReadingsVal($name,'anyoneElseAtHome',undef));
    readingsBulkUpdate($hash,'panic','off') if (!defined ReadingsVal($name,'panic',undef));
    readingsEndUpdate($hash,0);
  }
  Init($hash,$resdev) if ($init_done);
  return;
}

sub Undef
{
  my ($hash,$arg) = @_;
  RemoveInternalTimer($hash);
  my $name = $hash->{NAME};
  if (devspec2array('TYPE=HOMEMODE') == 1)
  {
    cleanUserattr($hash,$hash->{SENSORSBATTERY}) if ($hash->{SENSORSBATTERY});
    cleanUserattr($hash,$hash->{SENSORSCONTACT}) if ($hash->{SENSORSCONTACT});
    cleanUserattr($hash,$hash->{SENSORSENERGY}) if ($hash->{SENSORSENERGY});
    cleanUserattr($hash,$hash->{SENSORSLIGHT}) if ($hash->{SENSORSLIGHT});
    cleanUserattr($hash,$hash->{SENSORSMOTION}) if ($hash->{SENSORSMOTION});
    cleanUserattr($hash,$hash->{SENSORSPOWER}) if ($hash->{SENSORSPOWER});
    cleanUserattr($hash,$hash->{SENSORSSMOKE}) if ($hash->{SENSORSSMOKE});
    cleanUserattr($hash,$hash->{SENSORSTAMPER}) if ($hash->{SENSORSTAMPER});
    cleanUserattr($hash,$hash->{SENSORSWATER}) if ($hash->{SENSORSWATER});
  }
  return;
}

sub Init
{
  my ($hash,$resdev) = @_;
  my $name = $hash->{NAME};
  Log3 $name,4,"Init called";
  if (!$resdev)
  {
    my $text;
    my @resdevs;
    for (devspec2array('TYPE=RESIDENTS'))
    {
      push @resdevs,$_;
    }
    if (@resdevs == 1)
    {
      $text = $langDE?
        $resdevs[0].' existiert nicht':
        $resdevs[0].' doesn´t exists';
      return $text if (!ID($resdevs[0]));
      $hash->{DEF} = $resdevs[0];
    }
    elsif (@resdevs > 1)
    {
      $text = $langDE?
        'Es gibt zu viele RESIDENTS Geräte! Bitte das Master RESIDENTS Gerät angeben! Verfügbare RESIDENTS Geräte:':
        'Found too many available RESIDENTS devives! Please specify the RESIDENTS master device! Available RESIDENTS devices:';
      return "$text ".join(',',@resdevs);
    }
    else
    {
      $text = $langDE?
        'Kein RESIDENTS Gerät gefunden! Bitte erst ein RESIDENTS Gerät anlegen und ein paar ROOMMATE/GUEST/PET und ihre korrespondierenden PRESENCE Geräte hinzufügen um Spaß mit diesem Modul zu haben!':
        'No RESIDENTS device found! Please define a RESIDENTS device first and add some ROOMMATE/GUEST/PET and their PRESENCE device(s) to have fun with this module!';
      return $text;
    }
  }

  $hash->{helper}{migrate} = ReadingsVal($name,'.HOMEMODE_ver',1.5) < 1.6 ? 1 : 0;
  updateInternals($hash);
  Log3 $name,3,"$name: defined";
  return;
}

sub migrate
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my @tampers;
  my @tampread;
  for my $sen (split /,/x,InternalVal($name,'SENSORSCONTACT',''))
  {
    my ($con,$sab) = split ' ',AttrVal($sen,'HomeReadings',AttrVal($name,'HomeSensorsContactReadings','state sabotageError'));
    my $cv = AttrVal($sen,'HomeValues',AttrVal($name,'HomeSensorsContactValues','open|tilted|on'));
    push @tampread,$sab;
    if (ReadingsVal($sen,$con,undef))
    {
      CommandAttr(undef,$sen.' HomeReadingContact '.$con) if ($con ne 'state');
      CommandAttr(undef,$sen.' HomeValueContact '.$cv) if ($cv ne 'open|tilted|on');
    }
    if (ReadingsVal($sen,$sab,undef))
    {
      push @tampers,$sen;
      CommandAttr(undef,$sen.' HomeReadingTamper '.$sab) if ($sab ne 'sabotageError');
      CommandAttr(undef,$sen.' HomeValueTamper '.$cv) if ($cv ne 'open|tilted|on');
    }
    CommandDeleteAttr(undef,$sen.' HomeValues') if (AttrVal($sen,'HomeValues',undef));
    CommandDeleteAttr(undef,$sen.' HomeReadings') if (AttrVal($sen,'HomeReadings',undef));
  }
  for my $sen (split /,/x,InternalVal($name,'SENSORSMOTION',''))
  {
    my ($mo,$sab) = split ' ',AttrVal($sen,'HomeReadings',AttrVal($name,'HomeSensorsMotionReadings','state sabotageError'));
    my $mv = AttrVal($sen,'HomeValues',AttrVal($name,'HomeSensorsMotionValues','open|on|motion'));
    push @tampread,$sab;
    if (ReadingsVal($sen,$mo,undef))
    {
      CommandAttr(undef,$sen.' HomeReadingMotion '.$mo) if ($mo ne 'state');
      CommandAttr(undef,$sen.' HomeValueMotion '.$mv) if (!grep {$_ eq $mv} split /\|/x,'motion|open|on|1|true');
    }
    if (ReadingsVal($sen,$sab,undef))
    {
      push @tampers,$sen;
      CommandAttr(undef,$sen.' HomeReadingTamper '.$sab) if ($sab ne 'sabotageError');
      CommandAttr(undef,$sen.' HomeValueTamper '.$mv) if ($mv ne 'open|tilted|on');
    }
    CommandDeleteAttr(undef,$sen.' HomeValues') if (AttrVal($sen,'HomeValues',undef));
    CommandDeleteAttr(undef,$sen.' HomeReadings') if (AttrVal($sen,'HomeReadings',undef));
  }
  if (@tampers)
  {
    CommandAttr(undef,$name.' HomeSensorsTamper '.join(',',uniq sort @tampers)) if (!AttrVal($name,'HomeSensorsTamper',undef));
    @tampread = uniq @tampread;
    CommandAttr(undef,$name.' HomeSensorsTamperReading '.$tampread[0]) if (int(@tampread)==1 && !grep {$_ eq $tampread[0]} split /\|/x,'tampared|open|on|yes|1|true');
  }
  if (AttrVal($name,'HomeSensorsContactReadings',undef))
  {
    CommandAttr(undef,$name.' HomeSensorsContactReading '.(split ' ',AttrVal($name,'HomeSensorsContactReadings',''))[0]);
    CommandDeleteAttr(undef,$name.' HomeSensorsContactReadings');
  }
  if (AttrVal($name,'HomeSensorsMotionReadings',undef))
  {
    CommandAttr(undef,$name.' HomeSensorsMotionReading '.(split ' ',AttrVal($name,'HomeSensorsMotionReadings',''))[0]);
    CommandDeleteAttr(undef,$name.' HomeSensorsMotionReadings');
  }
  my $pe = AttrCheck($hash,'HomeSensorsPowerEnergy');
  if ($pe)
  {
    my ($pr,$er) = split ' ',AttrVal($name,'HomeSensorsPowerEnergyReadings','power energy');
    my @sensors;
    for my $s (devspec2array($pe))
    {
      next unless (ID($s,undef,$pr) && ID($s,undef,$er));
      push @sensors,$s;
    }
    my $list = join(',',uniq sort @sensors);
    CommandAttr(undef,$name.' HomeSensorsEnergy '.$list);
    CommandAttr(undef,$name.' HomeSensorsEnergyReading '.$er) if ($er ne 'energy');
    CommandAttr(undef,$name.' HomeSensorsPower '.$list);
    CommandAttr(undef,$name.' HomeSensorsPowerReading '.$pr) if ($pr ne 'power');
    CommandDeleteAttr(undef,$name.' HomeSensorsPowerEnergy');
    CommandDeleteAttr(undef,$name.' HomeSensorsPowerEnergyReadings') if (AttrVal($name,'HomeSensorsPowerEnergyReadings',undef));
  }
  if (AttrVal($name,'HomeYahooWeatherDevice',undef))
  {
    CommandAttr(undef,$name.' HomeWeatherDevice '.AttrVal($name,'HomeYahooWeatherDevice',undef));
    CommandDeleteAttr(undef,$name.' HomeYahooWeatherDevice');
  }
  if (AttrVal($name,'HomeAdvancedUserAttr',undef))
  {
    CommandAttr(undef,$name.' HomeAdvancedAttributes '.AttrVal($name,'HomeAdvancedUserAttr',undef));
    CommandDeleteAttr(undef,$name.' HomeAdvancedUserAttr');
  }
  if (AttrVal($name,'HomeTextNosmokeSmoke',undef))
  {
    CommandAttr(undef,$name.' HomeTextNoSmokeSmoke '.AttrVal($name,'HomeTextNosmokeSmoke',undef));
    CommandDeleteAttr(undef,$name.' HomeTextNosmokeSmoke');
  }
  if (AttrVal($name,'HomeSensorsSmokeValue',undef))
  {
    CommandAttr(undef,$name.' HomeSensorsSmokeValues '.AttrVal($name,'HomeSensorsSmokeValue',undef));
    CommandDeleteAttr(undef,$name.' HomeSensorsSmokeValue');
  }
  my $hehd = AttrVal($name,'HomeEventsHolidayDevices',undef);
  my $hecd = AttrVal($name,'HomeEventsCalendarDevices',undef);
  my @cals;
  if ($hehd)
  {
    for (devspec2array($hehd))
    {
      push @cals,$_;
    }
  }
  if ($hecd)
  {
    for (devspec2array($hecd))
    {
      push @cals,$_;
    }
  }
  CommandAttr(undef,$name.' HomeEventsDevices '.join(',',sort @cals)) if (int(@cals));
  CommandDeleteAttr(undef,$name.' HomeEventsHolidayDevices') if ($hehd);
  CommandDeleteAttr(undef,$name.' HomeEventsCalendarDevices') if ($hecd);
  readingsSingleUpdate($hash,'.HOMEMODE_ver',$ver,0);
  $hash->{helper}{migrate} = 0;
  updateInternals($hash,1,1);
  addSensorsUserAttr($hash,$hash->{NOTIFYDEV},$hash->{NOTIFYDEV});
  return;
}

sub GetUpdate
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  RemoveInternalTimer($hash,'FHEM::Automation::HOMEMODE::GetUpdate');
  return if (IsDis($name));
  my $mode = DayTime($hash);
  SetDaytime($hash);
  SetSeason($hash);
  CommandSet(undef,"$name:FILTER=mode!=$mode mode $mode") if (ReadingsVal($hash->{DEF},'state','') eq 'home' && AttrNum($name,'HomeAutoDaytime',1));
  checkIP($hash) if ((AttrNum($name,'HomePublicIpCheckInterval',0) && !$hash->{'.IP_TRIGGERTIME_NEXT'}) || (AttrNum($name,'HomePublicIpCheckInterval',0) && $hash->{'.IP_TRIGGERTIME_NEXT'} && $hash->{'.IP_TRIGGERTIME_NEXT'} < gettimeofday()));
  my $timer = gettimeofday() + 5;
  $hash->{'.TRIGGERTIME_NEXT'} = $timer;
  InternalTimer($timer,'FHEM::Automation::HOMEMODE::GetUpdate',$hash);
  return;
}

sub Notify
{
  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};
  my $devname = $dev->{NAME};
  return if (IsDis($name,$devname));
  my $devtype = $dev->{TYPE};
  my $events = deviceEvents($dev,1);
  return if (!$events);
  Log3 $name,5,"$name: Events from monitored device $devname: ". join ' --- ',@{$events};
  my $prestype = AttrVal($name,'HomePresenceDeviceType','PRESENCE');
  my @commands;
  if ($devname eq 'global')
  {
    if (grep {$_ eq 'INITIALIZED'} @{$events})
    {
      Init($hash,$defs{$name}{DEF});
      InternalTimer(gettimeofday()+30,'FHEM::Automation::HOMEMODE::AttrList',$hash);
      push @commands,AttrVal($name,'HomeCMDfhemINITIALIZED','') if (AttrVal($name,'HomeCMDfhemINITIALIZED',''));
    }
    elsif (grep {$_ eq 'SAVE'} @{$events})
    {
      push @commands,AttrVal($name,'HomeCMDfhemSAVE','') if (AttrVal($name,'HomeCMDfhemSAVE',''));
    }
    elsif (grep {$_ eq 'UPDATE'} @{$events})
    {
      push @commands,AttrVal($name,'HomeCMDfhemUPDATE','') if (AttrVal($name,'HomeCMDfhemUPDATE',''));
    }
    elsif (grep {/^DEFINED\s/} @{$events})
    {
      for my $evt (@{$events})
      {
        next unless ($evt =~ /^DEFINED\s(.+)$/);
        my $cal = $1;
        my $cmd = AttrVal($name,'HomeCMDfhemDEFINED','');
        if ($cmd)
        {
          $cmd =~ s/%DEFINED%/$cal/xgm;
          push @commands,$cmd;
        }
        CommandAttr(undef,"$cal room ".AttrVal($name,'HomeAtTmpRoom','')) if (AttrVal($name,'HomeAtTmpRoom','') && $cal =~ /^atTmp_.+_$name$/x && ID($cal,'at'));
        last;
      }
    }
    elsif (grep {/^REREADCFG|MODIFIED\s$name$/} @{$events})
    {
      updateInternals($hash,1,1);
    }
    elsif (grep {/^(DELETE)?ATTR\s.+$/} @{$events})
    {
      for my $evt (@{$events})
      {
        next unless ($evt =~ /^(DELETE)?ATTR\s.+$/);
        my @ev = split ' ',$evt;
        my $aname = $ev[1];
        my $aattr = $ev[2];
        my $avalue = $ev[3];
        if ($aattr =~ /^Home(BatteryLowPercentage|ReadingBattery)$/x)
        {
          my $aread = AttrVal($aname,'HomeReadingBattery',AttrVal($name,'HomeSensorsBatteryReading','battery'));
          my $read = $aattr eq 'HomeBatteryLowPercentage'?$aread:defined $avalue?$avalue:$aread;
          my $val  = ReadingsVal($aname,$read,100);
          CommandTrigger(undef,"$aname $read: $val");
        }
        Luminance($hash) if ($aattr eq 'HomeDividerLuminance');
        EnergyPower($hash,$1) if ($aattr =~ /^HomeDivider(Energy|Power)$/x);
        last;
      }
    }
  }
  else
  {
    if ($devtype =~ /^(RESIDENTS|ROOMMATE|GUEST|PET)$/x && grep {/^(state|wayhome|presence|location):\s/} @{$events})
    {
      RESIDENTS($hash,$devname);
    }
    elsif ($devname eq AttrVal($name,'HomeWeatherDevice',''))
    {
      Weather($hash,$devname);
    }
    elsif ($devname eq AttrVal($name,'HomeTwilightDevice',''))
    {
      Twilight($hash,$devname);
    }
    elsif ($devname eq AttrVal($name,'HomeUWZ','') && grep {/^WarnCount:\s/} @{$events})
    {
      UWZCommands($hash,$events);
    }
    elsif (grep {$_ eq $devname} split /,/x,InternalVal($name,'CALENDARS',''))
    {
      for my $evt (@{$events})
      {
        next unless ((ID($devname,'Calendar') && $evt =~ /^(start|end):\s(.+)$/) || (ID($devname,'holiday') && $evt =~ /^(state):\s(.+)$/));
        EventCommands($hash,$devname,$1,$2);
      }
    }
    else
    {
      if (AttrNum($name,'HomeAutoPresence',0) && $devtype =~ /^$prestype$/x && grep {/^presence:\s(absent|present|appeared|disappeared)$/} @{$events})
      {
        my $resident;
        my $residentregex;
        for (split /,/x,$hash->{RESIDENTS})
        {
          my $regex = $_;
          $regex =~ s/^(rr_|rg_|rp_)//x;
          next unless ($devname =~ /$regex/xi);
          $resident = $_;
          $residentregex = $regex;
          last;
        }
        if ($resident && $residentregex)
        {
          $hash->{helper}{lar} = $resident;
          my $residentstate = ReadingsVal($resident,'state','');
          my $suppressstate = '[gn]one|absent';
          if (ReadingsVal($devname,'presence','') !~ /^maybe/x)
          {
            my @presentdevicespresent;
            for my $device (devspec2array("TYPE=$prestype:FILTER=presence=^(maybe.)?(absent|present|appeared|disappeared)"))
            {
              next unless ($device =~ /$residentregex/xi);
              push @presentdevicespresent,$device if (ReadingsVal($device,'presence','') =~ /^(present|appeared|maybe.absent)$/x);
            }
            my $presdevspresent = int(@presentdevicespresent);
            Log3 $name,5,"$name: var presdevspresent=$presdevspresent";
            if (grep {/^presence:\s(present|appeared)$/} @{$events})
            {
              readingsBeginUpdate($hash);
              readingsBulkUpdate($hash,'lastActivityByPresenceDevice',$devname);
              readingsBulkUpdate($hash,'lastPresentByPresenceDevice',$devname);
              readingsEndUpdate($hash,1);
              push @commands,AttrVal($name,'HomeCMDpresence-present-device','') if (AttrVal($name,'HomeCMDpresence-present-device',undef));
              push @commands,AttrVal($name,"HomeCMDpresence-present-$resident-device",'') if (AttrVal($name,"HomeCMDpresence-present-$resident-device",undef));
              push @commands,AttrVal($name,"HomeCMDpresence-present-$resident-$devname",'') if (AttrVal($name,"HomeCMDpresence-present-$resident-$devname",undef));
              Log3 $name,5,"$name: attr HomePresenceDevicePresentCount-$resident=".AttrVal($name,"HomePresenceDevicePresentCount-$resident",'unset');
              if ($presdevspresent >= AttrNum($name,"HomePresenceDevicePresentCount-$resident",1)
                  && $residentstate =~ /^($suppressstate)$/x)
              {
                Log3 $name,5,"$name: set $resident:FILTER=state!=home state home";
                CommandSet(undef,"$resident:FILTER=state!=home state home");
              }
            }
            elsif (grep {/^presence:\s(absent|disappeared)$/} @{$events})
            {
              readingsBeginUpdate($hash);
              readingsBulkUpdate($hash,'lastActivityByPresenceDevice',$devname);
              readingsBulkUpdate($hash,'lastAbsentByPresenceDevice',$devname);
              readingsEndUpdate($hash,1);
              push @commands,AttrVal($name,'HomeCMDpresence-absent-device','') if (AttrVal($name,'HomeCMDpresence-absent-device',undef));
              push @commands,AttrVal($name,"HomeCMDpresence-absent-$resident-device",'') if (AttrVal($name,"HomeCMDpresence-absent-$resident-device",undef));
              push @commands,AttrVal($name,"HomeCMDpresence-absent-$resident-$devname",'') if (AttrVal($name,"HomeCMDpresence-absent-$resident-$devname",undef));
              my $devcount = 1;
              $devcount = int(@{$hash->{helper}{presdevs}{$resident}}) if ($hash->{helper}{presdevs}{$resident});
              my $presdevsabsent = $devcount - $presdevspresent;
              Log3 $name,5,"$name: var presdevsabsent=$presdevsabsent";
              $suppressstate .= '|'.AttrVal($name,'HomeAutoPresenceSuppressState','') if (AttrVal($name,'HomeAutoPresenceSuppressState',''));
              Log3 $name,5,"$name: attr HomePresenceDeviceAbsentCount-$resident=".AttrVal($name,"HomePresenceDeviceAbsentCount-$resident",'unset');
              if ($presdevsabsent >= AttrNum($name,"HomePresenceDeviceAbsentCount-$resident",1)
                  && $residentstate !~ /^$suppressstate$/x)
              {
                Log3 $name,5,"$name: set $resident:FILTER=state!=absent state absent";
                CommandSet(undef,"$resident:FILTER=state!=absent state absent");
              }
            }
          }
        }
      }
      if (AttrVal($name,'HomeTriggerPanic','') && $devname eq (split /:/x,AttrVal($name,'HomeTriggerPanic',''))[0])
      {
        my ($d,$r,$on,$off) = split /:/x,AttrVal($name,'HomeTriggerPanic','');
        if ($devname eq $d)
        {
          if (grep {$_ eq "$r: $on"} @{$events})
          {
            if ($off)
            {
              CommandSet(undef,"$name:FILTER=panic=off panic on");
            }
            else
            {
              if (ReadingsVal($name,'panic','off') eq 'off')
              {
                CommandSet(undef,"$name:FILTER=panic=off panic on");
              }
              else
              {
                CommandSet(undef,"$name:FILTER=panic=on panic off");
              }
            }
          }
          elsif ($off && grep {$_ eq "$r: $off"} @{$events})
          {
            CommandSet(undef,"$name:FILTER=panic=on panic off");
          }
        }
      }
      if (AttrVal($name,'HomeTriggerAnyoneElseAtHome','') && $devname eq (split /:/x,AttrVal($name,'HomeTriggerAnyoneElseAtHome',''))[0])
      {
        my (undef,$r,$on,$off) = split /:/x,AttrVal($name,'HomeTriggerAnyoneElseAtHome','');
        if (grep {$_ eq "$r: $on"} @{$events})
        {
          CommandSet(undef,"$name:FILTER=anyoneElseAtHome=off anyoneElseAtHome on");
        }
        elsif (grep {$_ eq "$r: $off"} @{$events})
        {
          CommandSet(undef,"$name:FILTER=anyoneElseAtHome=on anyoneElseAtHome off");
        }
      }
      if (AttrVal($name,'HomeSensorTemperatureOutside',undef) && $devname eq AttrVal($name,'HomeSensorTemperatureOutside','') && grep {/^(temperature|humidity):\s/} @{$events})
      {
        my $temp;
        my $humi;
        for my $evt (@{$events})
        {
          next unless ($evt =~ /^(humidity|temperature):\s(.+)$/);
          $temp = (split ' ',$2)[0] if ($1 eq 'temperature');
          $humi = (split ' ',$2)[0] if ($1 eq 'humidity');
        }
        if (defined $temp)
        {
          readingsSingleUpdate($hash,'temperature',$temp,1);
          ReadingTrend($hash,'temperature',$temp);
          Icewarning($hash);
        }
        if (defined $humi && !AttrVal($name,'HomeSensorHumidityOutside',undef))
        {
          readingsSingleUpdate($hash,'humidity',$humi,1);
          ReadingTrend($hash,'humidity',$humi);
        }
        Weather($hash,AttrVal($name,'HomeWeatherDevice','')) if (AttrVal($name,'HomeWeatherDevice',''));
      }
      if (AttrVal($name,'HomeSensorHumidityOutside',undef) && $devname eq AttrVal($name,'HomeSensorHumidityOutside','') && grep {/^humidity:\s/} @{$events})
      {
        for my $evt (@{$events})
        {
          next unless ($evt =~ /^humidity:\s(.+)$/);
          my $val = (split ' ',$1)[0];
          readingsSingleUpdate($hash,'humidity',$val,1);
          ReadingTrend($hash,'humidity',$val);
          Weather($hash,AttrVal($name,'HomeWeatherDevice','')) if (AttrVal($name,'HomeWeatherDevice',''));
          last;
        }
      }
      if (AttrVal($name,'HomeSensorWindspeed',undef) && $devname eq (split /:/x,AttrVal($name,'HomeSensorWindspeed',''))[0])
      {
        my $read = (split /:/x,AttrVal($name,'HomeSensorWindspeed',''))[1];
        if (grep {/^$read:\s(.+)$/} @{$events})
        {
          for my $evt (@{$events})
          {
            next unless ($evt =~ /^$read:\s(.+)$/);
            my $val = (split ' ',$1)[0];
            readingsSingleUpdate($hash,'wind',$val,1);
            ReadingTrend($hash,'wind',$val);
            Weather($hash,AttrVal($name,'HomeWeatherDevice','')) if (AttrVal($name,'HomeWeatherDevice',''));
            last;
          }
        }
      }
      if (AttrVal($name,'HomeSensorAirpressure',undef) && $devname eq (split /:/x,AttrVal($name,'HomeSensorAirpressure',''))[0])
      {
        my $read = (split /:/x,AttrVal($name,'HomeSensorAirpressure',''))[1];
        if (grep {/^$read:\s(.+)$/} @{$events})
        {
          for my $evt (@{$events})
          {
            next unless ($evt =~ /^$read:\s(.+)$/);
            my $val = (split ' ',$1)[0];
            readingsSingleUpdate($hash,'pressure',$val,1);
            ReadingTrend($hash,'pressure',$val);
            Weather($hash,AttrVal($name,'HomeWeatherDevice','')) if (AttrVal($name,'HomeWeatherDevice',''));
            last;
          }
        }
      }
      if (grep {$_ eq $devname} split /,/x,InternalVal($name,'SENSORSBATTERY',''))
      {
        my $read = AttrVal($devname,'HomeReadingBattery',AttrVal($name,'HomeSensorsBatteryReading','battery'));
        my $pct = AttrNum($devname,'HomeBatteryLowPercentage',AttrNum($name,'HomeSensorsBatteryLowPercentage',30));
        if (grep {/^$read:\s(.+)$/} @{$events})
        {
          my @lowOld = split /,/x,ReadingsVal($name,'batteryLow','');
          my @low;
          @low = @lowOld if (@lowOld);
          for my $evt (@{$events})
          {
            next unless ($evt =~ /^$read:\s(.+)$/);
            my $val = $1;
            inform($hash,"$devname.$read",$val);
            if (($val =~ /^(\d{1,3})(%|\s%)?$/ && $1 <= $pct) || $val =~ /^(nok|low)$/x)
            {
              push @low,$devname if (!grep {$_ eq $devname} @low);
            }
            elsif (grep {$_ eq $devname} @low)
            {
              my @lown;
              for (@low)
              {
                push @lown,$_ if ($_ ne $devname);
              }
              @low = @lown;
            }
            last;
          }
          readingsBeginUpdate($hash);
          if (@low)
          {
            readingsBulkUpdateIfChanged($hash,'batteryLow',join(',',@low));
            readingsBulkUpdateIfChanged($hash,'batteryLow_ct',int(@low));
            readingsBulkUpdateIfChanged($hash,'batteryLow_hr',makeHR($hash,1,@low));
            readingsBulkUpdateIfChanged($hash,'lastBatteryLow',$devname) if (grep {$_ eq $devname} @low && !grep {$_ eq $devname} @lowOld);
          }
          else
          {
            readingsBulkUpdateIfChanged($hash,'batteryLow','');
            readingsBulkUpdateIfChanged($hash,'batteryLow_ct',int(@low));
            readingsBulkUpdateIfChanged($hash,'batteryLow_hr','');
          }
          readingsBulkUpdateIfChanged($hash,'lastBatteryNormal',$devname) if (!grep {$_ eq $devname} @low && grep {$_ eq $devname} @lowOld);
          readingsEndUpdate($hash,1);
          push @commands,AttrVal($name,'HomeCMDbattery','') if (AttrVal($name,'HomeCMDbattery',undef) && (grep {$_ eq $devname} @low || grep {$_ eq $devname} @lowOld));
          push @commands,AttrVal($name,'HomeCMDbatteryLow','') if (AttrVal($name,'HomeCMDbatteryLow',undef) && grep {$_ eq $devname} @low && !grep {$_ eq $devname} @lowOld);
          push @commands,AttrVal($name,'HomeCMDbatteryNormal','') if (AttrVal($name,'HomeCMDbatteryNormal',undef) && !grep {$_ eq $devname} @low && grep {$_ eq $devname} @lowOld);
        }
      }
      if (grep {$_ eq $devname} split /,/x,InternalVal($name,'SENSORSCONTACT',''))
      {
        my $read = AttrVal($devname,'HomeReadingContact',AttrVal($name,'HomeSensorsContactReading','state'));
        if (grep {/^$read:\s(.+)$/} @{$events})
        {
          TriggerState($hash,undef,undef,$devname);
          my $val;
          for my $evt (@{$events})
          {
            next if ($evt !~ /^$read:\s(.+)$/);
            $val = $1;
            last;
          }
          inform($hash,"$devname.$read",$val);
        }
      }
      if (grep {$_ eq $devname} split /,/x,InternalVal($name,'SENSORSENERGY',''))
      {
        my $read = AttrVal($devname,'HomeReadingEnergy',AttrVal($name,'HomeSensorsEnergyReading','energy'));
        for my $evt (@{$events})
        {
          next unless ($evt =~ /^$read:\s(.+)$/);
          EnergyPower($hash,'Energy');
          inform($hash,"$devname.$read",$1);
          last;
        }
      }
      if (grep {$_ eq $devname} split /,/x,InternalVal($name,'SENSORSLIGHT',''))
      {
        my $read = AttrVal($devname,'HomeReadingLuminance',AttrVal($name,'HomeSensorsLuminanceReading','luminance'));
        Luminance($hash) if (grep {/^$read:\s.+$/} @{$events});
      }
      if (grep {$_ eq $devname} split /,/x,InternalVal($name,'SENSORSMOTION',''))
      {
        my $read = AttrVal($devname,'HomeReadingMotion',AttrVal($name,'HomeSensorsMotionReading','state'));
        if (grep {/^$read:\s.+$/} @{$events})
        {
          TriggerState($hash,undef,undef,$devname);
          my $val;
          for my $v (@{$events})
          {
            next if ($v !~ /^$read:\s(.+)$/);
            $val = $1;
            last;
          }
          inform($hash,"$devname.$read",$val);
        }
      }
      if (grep {$_ eq $devname} split /,/x,InternalVal($name,'SENSORSPOWER',''))
      {
        my $read = AttrVal($devname,'HomeReadingPower',AttrVal($name,'HomeSensorsPowerReading','power'));
        for my $evt (@{$events})
        {
          next unless ($evt =~ /^$read:\s(.*)$/);
          EnergyPower($hash,'Power');
          inform($hash,"$devname.$read",$1);
          last;
        }
      }
      if (grep {$_ eq $devname} split /,/x,InternalVal($name,'SENSORSSMOKE',''))
      {
        my $read = AttrVal($devname,'HomeReadingSmoke',AttrVal($name,'HomeSensorsSmokeReading','state'));
        for my $evt (@{$events})
        {
          next unless ($evt =~ /^$read:\s(.+)$/);
          twoStateSensor($hash,'Smoke',$devname,$1);
          inform($hash,"$devname.$read",$1);
          last;
        }
      }
      if (grep {$_ eq $devname} split /,/x,InternalVal($name,'SENSORSTAMPER',''))
      {
        my $read = AttrVal($devname,'HomeReadingTamper',AttrVal($name,'HomeSensorsTamperReading','sabotageError'));
        for my $evt (@{$events})
        {
          next unless ($evt =~ /^$read:\s(.*)$/);
          twoStateSensor($hash,'Tamper',$devname,$1);
          inform($hash,"$devname.$read",$1);
          last;
        }
      }
      if (grep {$_ eq $devname} split /,/x,InternalVal($name,'SENSORSWATER',''))
      {
        my $read = AttrVal($devname,'HomeReadingWater',AttrVal($name,'HomeSensorsWaterReading','state'));
        for my $evt (@{$events})
        {
          next unless ($evt =~ /^$read:\s(.*)$/);
          twoStateSensor($hash,'Water',$devname,$1);
          inform($hash,"$devname.$read",$1);
          last;
        }
      }
    }
  }
  execCMDs($hash,serializeCMD($hash,@commands)) if (@commands);
  GetUpdate($hash) if (!$hash->{'.TRIGGERTIME_NEXT'} || $hash->{'.TRIGGERTIME_NEXT'} + 1 < gettimeofday());
  return;
}

sub updateInternals
{
  my ($hash,$force,$setter) = @_;
  my $name = $hash->{NAME};
  my $resdev = $hash->{DEF};
  my $text;
  if (!ID($resdev))
  {
    $text = $langDE?
      "$resdev ist nicht definiert!":
      "$resdev is not defined!";
    readingsSingleUpdate($hash,'state',$text,0);
  }
  elsif (!ID($resdev,'RESIDENTS'))
  {
    $text = $langDE?
      "$resdev ist kein gültiges RESIDENTS Gerät!":
      "$resdev is not a valid RESIDENTS device!";
    readingsSingleUpdate($hash,'state',$text,0);
  }
  else
  {
    my $oldBatts = $hash->{SENSORSBATTERY} // '';
    my $oldContacts = $hash->{SENSORSCONTACT} // '';
    my $oldEnergies = $hash->{SENSORSENERGY} // '';
    my $oldLumis = $hash->{SENSORSLIGHT} // '';
    my $oldMotions = $hash->{SENSORSMOTION} // '';
    my $oldPowers = $hash->{SENSORSPOWER} // '';
    my $oldSmokes = $hash->{SENSORSSMOKE} // '';
    my $oldTampers = $hash->{SENSORSTAMPER} // '';
    my $oldWaters = $hash->{SENSORSWATER} // '';
    delete $hash->{helper}{presdevs};
    delete $hash->{RESIDENTS};
    delete $hash->{SENSORSBATTERY};
    delete $hash->{SENSORSCONTACT};
    delete $hash->{SENSORSENERGY};
    delete $hash->{SENSORSLIGHT};
    delete $hash->{SENSORSMOTION};
    delete $hash->{SENSORSPOWER};
    delete $hash->{SENSORSTAMPER};
    delete $hash->{SENSORSSMOKE};
    delete $hash->{SENSORSWATER};
    delete $hash->{CALENDARS};
    $hash->{VERSION} = $HOMEMODE_version;
    my @residents;
    push @residents,$defs{$resdev}->{ROOMMATES} if ($defs{$resdev}->{ROOMMATES});
    push @residents,$defs{$resdev}->{GUESTS} if ($defs{$resdev}->{GUESTS});
    push @residents,$defs{$resdev}->{PETS} if ($defs{$resdev}->{PETS});
    if (@residents < 1)
    {
      $text = $langDE?
        "Keine verfügbaren ROOMMATE/GUEST/PET im RESIDENTS Gerät $resdev":
        "No available ROOMMATE/GUEST/PET in RESIDENTS device $resdev";
      Log3 $name,2,$text;
      readingsSingleUpdate($hash,'HomeInfo',$text,1);
      return;
    }
    else
    {
      $hash->{RESIDENTS} = join(',',sort @residents);
    }
    my @allMonitoredDevices = ('global');
    push @allMonitoredDevices,$resdev if ($resdev);
    my $autopresence = AttrCheck($hash,'HomeAutoPresence',0);
    my $presencetype = AttrCheck($hash,'HomePresenceDeviceType','PRESENCE');
    my @presdevs = devspec2array("TYPE=$presencetype:FILTER=presence=^(maybe.)?(absent|present|appeared|disappeared)");
    my @residentsshort;
    my @logtexte;
    for my $resident (split /,/x,$hash->{RESIDENTS})
    {
      push @allMonitoredDevices,$resident;
      my $short = $resident;
      $short =~ s/^r[rgp]_//x;
      push @residentsshort,$short;
      if ($autopresence)
      {
        my @residentspresdevs;
        for my $p (@presdevs)
        {
          next unless ($p =~ /$short/xi);
          push @residentspresdevs,$p;
          push @allMonitoredDevices,$p;
        }
        if (@residentspresdevs)
        {
          my $c = int(@residentspresdevs);
          my $devlist = join(',',@residentspresdevs);
          $text = $langDE?
            "Gefunden wurden $c übereinstimmende(s) Anwesenheits Gerät(e) vom Devspec \"TYPE=$presencetype\" für Bewohner \"$resident\"! Übereinstimmende Geräte: \"$devlist\"":
            "Found $c matching presence devices of devspec \"TYPE=$presencetype\" for resident \"$resident\"! Matching devices: \"$devlist\"";
          push @logtexte,$text;
          CommandAttr(undef,"$name HomePresenceDeviceAbsentCount-$resident $c") if ($init_done && ((!defined AttrNum($name,"HomePresenceDeviceAbsentCount-$resident",undef) && $c > 1) || (AttrNum($name,"HomePresenceDeviceAbsentCount-$resident",undef) && $c < AttrNum($name,"HomePresenceDeviceAbsentCount-$resident",1))));
        }
        else
        {
          $text = $langDE?
            "Keine Geräte mit presence Reading gefunden vom Devspec \"TYPE=$presencetype\" für Bewohner \"$resident\"!":
            "No devices with presence reading found of devspec \"TYPE=$presencetype\" for resident \"$resident\"!";
          push @logtexte,$text;
        }
        $hash->{helper}{presdevs}{$resident} = \@residentspresdevs if (@residentspresdevs > 1);
      }
    }
    if (@logtexte && $setter)
    {
      $text = $langDE?
        'Falls ein oder mehr Anweseheits Geräte falsch zugeordnet wurden, so benenne diese bitte so um dass die Bewohner Namen ('.join(',',@residentsshort).") nicht Bestandteil des Namen sind.\nNach dem Umbenennen führe einfach \"set $name updateInternalsForce\" aus um diese Überprüfung zu wiederholen.":
        'If any recognized presence device is wrong, please rename this device so that it will NOT match the residents names ('.join(',',@residentsshort).") somewhere in the device name.\nAfter renaming simply execute \"set $name updateInternalsForce\" to redo this check.";
      push @logtexte,"\n$text";
      my $log = join('\n',@logtexte);
      Log3 $name,3,"$name: $log";
      $log =~ s/\n/<br>/xgm;
      readingsSingleUpdate($hash,'HomeInfo',"<html>$log</html>",1);
    }
    my $migrate = $hash->{helper}{migrate};
    my $contacts = AttrCheck($hash,'HomeSensorsContact');
    if ($contacts)
    {
      my @sensors;
      for my $s (devspec2array($contacts))
      {
        push @sensors,$s;
        push @allMonitoredDevices,$s;
      }
      my $list = join(',',sort @sensors);
      $hash->{SENSORSCONTACT} = $list;
      addSensorsUserAttr($hash,$list,$oldContacts) if ($migrate || ($force && !$oldContacts) || ($oldContacts && $list ne $oldContacts));
    }
    elsif (!$contacts && $oldContacts)
    {
      cleanUserattr($hash,$oldContacts);
    }
    my $motion = AttrCheck($hash,'HomeSensorsMotion');
    if ($motion)
    {
      my @sensors;
      for my $s (devspec2array($motion))
      {
        push @sensors,$s;
        push @allMonitoredDevices,$s;
      }
      my $list = join(',',sort @sensors);
      $hash->{SENSORSMOTION} = $list;
      addSensorsUserAttr($hash,$list,$oldMotions) if ($migrate || ($force && !$oldMotions) || ($oldMotions && $list ne $oldMotions));
    }
    elsif (!$motion && $oldMotions)
    {
      cleanUserattr($hash,$oldMotions);
    }
    my $energy = AttrCheck($hash,'HomeSensorsEnergy');
    if ($energy)
    {
      my @sensors;
      for my $s (devspec2array($energy))
      {
        push @sensors,$s;
        push @allMonitoredDevices,$s;
      }
      my $list = join(',',sort @sensors);
      $hash->{SENSORSENERGY} = $list;
      addSensorsUserAttr($hash,$list,$oldEnergies) if ($migrate || ($force && !$oldEnergies) || ($oldEnergies && $list ne $oldEnergies));
    }
    elsif (!$energy && $oldEnergies)
    {
      cleanUserattr($hash,$oldEnergies);
    }
    my $power = AttrCheck($hash,'HomeSensorsPower');
    if ($power)
    {
      my @sensors;
      for my $s (devspec2array($power))
      {
        push @sensors,$s;
        push @allMonitoredDevices,$s;
      }
      my $list = join(',',sort @sensors);
      $hash->{SENSORSPOWER} = $list;
      addSensorsUserAttr($hash,$list,$oldPowers) if ($migrate || ($force && !$oldPowers) || ($oldPowers && $list ne $oldPowers));
    }
    elsif (!$power && $oldPowers)
    {
      cleanUserattr($hash,$oldPowers);
    }
    my $tamper = AttrCheck($hash,'HomeSensorsTamper');
    if ($tamper)
    {
      my @sensors;
      for my $s (devspec2array($tamper))
      {
        push @sensors,$s;
        push @allMonitoredDevices,$s;
      }
      my $list = join(',',sort @sensors);
      $hash->{SENSORSTAMPER} = $list;
      addSensorsUserAttr($hash,$list,$oldTampers) if ($migrate || ($force && !$oldTampers) || ($oldTampers && $list ne $oldTampers));
    }
    elsif (!$tamper && $oldTampers)
    {
      cleanUserattr($hash,$oldTampers);
    }
    my $smoke = AttrCheck($hash,'HomeSensorsSmoke');
    if ($smoke)
    {
      my @sensors;
      for my $s (devspec2array($smoke))
      {
        push @sensors,$s;
        push @allMonitoredDevices,$s;
      }
      my $list = join(',',sort @sensors);
      $hash->{SENSORSSMOKE} = $list;
      addSensorsUserAttr($hash,$list,$oldSmokes) if ($migrate || ($force && !$oldSmokes) || ($oldSmokes && $list ne $oldSmokes));
    }
    elsif (!$smoke && $oldSmokes)
    {
      cleanUserattr($hash,$oldSmokes);
    }
    my $water = AttrCheck($hash,'HomeSensorsWater');
    if ($water)
    {
      my @sensors;
      for my $s (devspec2array($water))
      {
        push @sensors,$s;
        push @allMonitoredDevices,$s;
      }
      my $list = join(',',sort @sensors);
      $hash->{SENSORSWATER} = $list;
      addSensorsUserAttr($hash,$list,$oldWaters) if ($migrate || ($force && !$oldWaters) || ($oldWaters && $list ne $oldWaters));
    }
    elsif (!$water && $oldWaters)
    {
      cleanUserattr($hash,$oldWaters);
    }
    my $battery = AttrCheck($hash,'HomeSensorsBattery');
    if ($battery)
    {
      my @sensors;
      for my $s (devspec2array($battery))
      {
        my @reads = split ' ',AttrVal($name,'HomeSensorsBatteryReading','battery batteryState batteryPercent');
        for my $r (@reads)
        {
          my $val = ReadingsVal($s,$r,'');
          next unless ($val =~ /^(ok|low|nok|\d{1,3})(%|\s%)?$/);
          push @sensors,$s;
          push @allMonitoredDevices,$s;
          if (!grep {$_ eq $s} split /,/x,ReadingsVal($name,'batteryLow',''))
          {
            CommandTrigger(undef,"$s $r: ok") if ($val =~ /^(low|nok)$/x);
            CommandTrigger(undef,"$s $r: 100") if ($val =~ /^\d{1,3}$/x);
            CommandTrigger(undef,"$s $r: 100%") if ($val =~ /^\d{1,3}%$/x);
            CommandTrigger(undef,"$s $r: 100 %") if ($val =~ /^\d{1,3}\s%$/);
            CommandTrigger(undef,"$s $r: $val");
          }
        }
      }
      my $list = join(',',uniq sort @sensors);
      $hash->{SENSORSBATTERY} = $list;
      addSensorsUserAttr($hash,$list,$oldBatts) if ($migrate || ($force && !$oldBatts) || ($oldBatts && $list ne $oldBatts));
    }
    elsif (!$battery && $oldBatts)
    {
      cleanUserattr($hash,$oldBatts);
    }
    my $luminance = AttrCheck($hash,'HomeSensorsLuminance');
    if ($luminance)
    {
      my @sensors;
      for my $s (devspec2array($luminance))
      {
        push @sensors,$s;
        push @allMonitoredDevices,$s;
      }
      my $list = join(',',sort @sensors);
      $hash->{SENSORSLIGHT} = $list;
    }
    my $weather = AttrCheck($hash,'HomeWeatherDevice');
    push @allMonitoredDevices,$weather if ($weather);
    my $twilight = AttrCheck($hash,'HomeTwilightDevice');
    push @allMonitoredDevices,$twilight if ($twilight);
    my $temperature = AttrCheck($hash,'HomeSensorTemperatureOutside');
    push @allMonitoredDevices,$temperature if ($temperature);
    my $humidity = AttrCheck($hash,'HomeSensorHumidityOutside');
    push @allMonitoredDevices,$humidity if ($humidity);
    CommandDeleteReading(undef,"$name event-.+");
    my $calendar = AttrCheck($hash,'HomeEventsDevices');
    if ($calendar)
    {
      my @cals;
      for my $c (devspec2array($calendar))
      {
        push @cals,$c;
        push @allMonitoredDevices,$c;
        if (ID($c,'Calendar'))
        {
          EventCommands($hash,$c,'modeStarted',ReadingsVal($c,'modeStarted','none'));
        }
        else
        {
          readingsSingleUpdate($hash,"event-$c",ReadingsVal($c,'state','none'),1);
        }
      }
      my $list = join(',',uniq sort @cals);
      $hash->{CALENDARS} = $list;
    }
    my $uwz = AttrCheck($hash,'HomeUWZ','');
    push @allMonitoredDevices,$uwz;
    my $pressure = (split /:/x,AttrCheck($hash,'HomeSensorAirpressure'))[0];
    push @allMonitoredDevices,$pressure if ($pressure);
    my $wind = (split /:/x,AttrCheck($hash,'HomeSensorWindspeed'))[0];
    push @allMonitoredDevices,$wind if ($wind);
    my $panic = (split /:/x,AttrCheck($hash,'HomeTriggerPanic'))[0];
    push @allMonitoredDevices,$panic if ($panic);
    my $aeah = (split /:/x,AttrCheck($hash,'HomeTriggerAnyoneElseAtHome'))[0];
    push @allMonitoredDevices,$aeah if ($aeah);
    @allMonitoredDevices = uniq sort @allMonitoredDevices;
    Log3 $name,5,"$name: new monitored device count: ".@allMonitoredDevices;
    $hash->{NOTIFYDEV} = join(',',@allMonitoredDevices);
    GetUpdate($hash);
    return if (!@allMonitoredDevices);
    AttrList($hash);
    return migrate($hash) if ($hash->{helper}{migrate});
    RESIDENTS($hash);
    TriggerState($hash) if ($hash->{SENSORSCONTACT} || $hash->{SENSORSMOTION});
    Luminance($hash) if ($hash->{SENSORSLIGHT});
    EnergyPower($hash,'Energy') if ($hash->{SENSORSENERGY});
    EnergyPower($hash,'Power') if ($hash->{SENSORSPOWER});
    twoStateSensor($hash,'Smoke') if ($hash->{SENSORSSMOKE});
    twoStateSensor($hash,'Tamper') if ($hash->{SENSORSTAMPER});
    twoStateSensor($hash,'Water') if ($hash->{SENSORSWATER});
    Weather($hash,$weather) if ($weather);
    Twilight($hash,$twilight,1) if ($twilight);
    ToggleDevice($hash,undef);
    readingsSingleUpdate($hash,'.HOMEMODE_ver',$ver,0);
  }
  return;
}

sub Get
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  return if (IsDis($name) && $cmd ne '?');
  my $params = 'mode:noArg modeAlarm:noArg publicIP:noArg devicesDisabled:noArg';
  $params .= ' contactsOpen:all,doorsinside,doorsoutside,doorsmain,outside,windows' if ($hash->{SENSORSCONTACT});
  $params .= ' sensorsTampered:noArg' if ($hash->{SENSORSCONTACT} || $hash->{SENSORSMOTION});
  if (AttrVal($name,'HomeWeatherDevice',undef))
  {
    if (AttrVal($name,'HomeTextWeatherLong',undef) || AttrVal($name,'HomeTextWeatherShort',undef))
    {
      $params .= ' weather:';
      $params .= 'long' if (AttrVal($name,'HomeTextWeatherLong',undef));
      $params .= ',' if (AttrVal($name,'HomeTextWeatherLong',undef) && AttrVal($name,'HomeTextWeatherShort',undef));
      $params .= 'short' if (AttrVal($name,'HomeTextWeatherShort',undef))
    }
    $params .= ' weatherForecast' if (AttrVal($name,'HomeTextWeatherLong',undef));
  }
  my $value = $args[0];
  my $text;
  if ($cmd eq 'devicesDisabled')
  {
    return join '\n',split /,/x,ReadingsVal($name,'devicesDisabled','none');
  }
  elsif ($cmd eq 'mode')
  {
    return ReadingsVal($name,'mode','no mode available');
  }
  elsif ($cmd eq 'modeAlarm')
  {
    return ReadingsVal($name,'modeAlarm','no modeAlarm available');
  }
  elsif ($cmd eq 'contactsOpen')
  {
    $text = $langDE?
      "$cmd benötigt ein Argument":
      "$cmd needs one argument!";
    return $text if (!$value);
    TriggerState($hash,$cmd,$value);
  }
  elsif ($cmd eq 'sensorsTampered')
  {
    $text = $langDE?
      "$cmd benötigt kein Argument":
      "$cmd needs no argument!";
    return $text if ($value);
    return ReadingsVal($name,'alarmTampered','-');
  }
  elsif ($cmd eq 'weather')
  {
    $text = $langDE?
      "$cmd benötigt ein Argument, entweder long oder short!":
      "$cmd needs one argument of long or short!";
    return $text if (!$value || $value !~ /^long|short$/x);
    my $m = $value eq 'short'?'Short':'Long';
    WeatherTXT($hash,AttrVal($name,"HomeTextWeather$m",''));
  }
  elsif ($cmd eq 'weatherForecast')
  {
    $text = $langDE?
      "Der Wert für $cmd muss zwischen 1 und 10 sein. Falls der Wert weggelassen wird, so wird 2 (für morgen) benutzt.":
      "Value for $cmd must be from 1 to 10. If omitted the value will be 2 for tomorrow.";
    return $text if ($value && $value !~ /^[1-9]0?$/x && ($value < 1 || $value > 10));
    ForecastTXT($hash,$value);
  }
  elsif ($cmd eq 'publicIP')
  {
    return checkIP($hash);
  }
  else
  {
    return "Unknown argument $cmd for $name, choose one of $params";
  }
  return;
}

sub Set
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  return if (IsDis($name) && $cmd ne '?');
  $langDE = AttrVal('global','language','EN') eq 'DE' || AttrVal($name,'HomeLanguage','EN') eq 'DE' ? 1 : 0;
  my $text = $langDE?
    '"set '.$name.'" benötigt mindestens ein und maximal drei Argumente':
    '"set '.$name.'" needs at least one argument and maximum three arguments';
  return $text if (@aa > 3);
  my $option = defined $args[0] ? $args[0] : undef;
  my $value = defined $args[1] ? $args[1] : undef;
  my $mode = ReadingsVal($name,'mode','');
  my $amode = ReadingsVal($name,'modeAlarm','');
  my $plocation = ReadingsVal($name,'location','');
  my $presence = ReadingsVal($name,'presence','');
  my @locations = split /,/x,$HOMEMODE_Locations;
  my $slocations = AttrCheck($hash,'HomeSpecialLocations');
  if ($slocations)
  {
    for (split /,/x,$slocations)
    {
      push @locations,$_;
    }
  }
  my @modeparams = split /,/x,$HOMEMODE_UserModesAll;
  my $smodes = AttrCheck($hash,'HomeSpecialModes');
  if ($smodes)
  {
    for (split /,/x,$smodes)
    {
      push @modeparams,$_;
    }
  }
  my @sensorsSet;
  push @sensorsSet,'all' if ($hash->{SENSORSCONTACT} || $hash->{SENSORSMOTION} || $hash->{SENSORSBATTERY} || $hash->{SENSORSENERGY} || $hash->{SENSORSPOWER} || $hash->{SENSORSLIGHT} || $hash->{SENSORSSMOKE} || $hash->{SENSORSTAMPER});
  push @sensorsSet,'sensorsContact' if ($hash->{SENSORSCONTACT});
  push @sensorsSet,'sensorsMotion' if ($hash->{SENSORSMOTION});
  push @sensorsSet,'sensorsBattery' if ($hash->{SENSORSBATTERY});
  push @sensorsSet,'sensorsSmoke' if ($hash->{SENSORSSMOKE});
  push @sensorsSet,'sensorsEnergy' if ($hash->{SENSORSENERGY});
  push @sensorsSet,'sensorsPower' if ($hash->{SENSORSPOWER});
  push @sensorsSet,'sensorsTamper' if ($hash->{SENSORSTAMPER});
  push @sensorsSet,'sensorsLuminance' if ($hash->{SENSORSLIGHT});
  my $readd = join(',',sort @sensorsSet);
  my $para;
  $para .= 'mode:'.join(',',sort @modeparams).' ' if (!AttrNum($name,'HomeAutoDaytime',1));
  $para .= 'anyoneElseAtHome:on,off';
  $para .= ' deviceDisable:';
  $para .= $hash->{helper}{enabledDevices} ? $hash->{helper}{enabledDevices} : 'noArg';
  $para .= ' deviceEnable:';
  $para .= ReadingsVal($name,'devicesDisabled','') ? ReadingsVal($name,'devicesDisabled','') : 'noArg';
  $para .= ' dnd:on,off';
  $para .= ' dnd-for-minutes';
  $para .= ' location:'.join(',', uniq sort @locations);
  $para .= ' modeAlarm:'.$HOMEMODE_AlarmModes;
  $para .= ' modeAlarm-for-minutes';
  $para .= ' panic:on,off';
  $para .= ' updateInternalsForce:noArg';
  $para .= ' updateHomebridgeMapping:noArg';
  $para .= ' updateSensorsUserattr:noArg' if ($readd);
  return "$cmd is not a valid command for $name, please choose one of $para" if (!$cmd || $cmd eq '?');
  my @commands;
  if ($cmd eq 'mode')
  {
    my $namode = 'disarm';
    my $present = 'absent';
    my $location = 'underway';
    $option = DayTime($hash) if ($option && $option eq 'home' && AttrNum($name,'HomeAutoDaytime',1));
    if ($option !~ /^absent|gone$/x)
    {
      push @commands,AttrVal($name,'HomeCMDpresence-present','') if (AttrVal($name,'HomeCMDpresence-present',undef) && $mode =~ /^(absent|gone)$/x);
      $present = 'present';
      $location = (grep {/^$plocation$/x} split /,/x,$slocations) ? $plocation : 'home';
      if ($presence eq 'absent')
      {
        if (AttrNum($name,'HomeAutoArrival',0))
        {
          my $hour = hourMaker(AttrNum($name,'HomeAutoArrival',0));
          CommandDelete(undef,"atTmp_set_home_$name") if (ID("atTmp_set_home_$name",'at'));
          CommandDefine(undef,"atTmp_set_home_$name at +$hour set $name:FILTER=location=arrival location home");
          $location = 'arrival';
        }
      }
      if ($option eq 'asleep')
      {
        $namode = 'armnight';
        $location = 'bed';
      }
    }
    elsif ($option =~ /^absent|gone$/x)
    {
      push @commands,AttrVal($name,'HomeCMDpresence-absent','') if (AttrVal($name,'HomeCMDpresence-absent',undef) && $mode !~ /^absent|gone$/x);
      $namode = ReadingsVal($name,'anyoneElseAtHome','off') eq 'off' ? 'armaway':'armhome';
      if (AttrNum($name,'HomeModeAbsentBelatedTime',0) && AttrVal($name,'HomeCMDmode-absent-belated',undef))
      {
        my $hour = hourMaker(AttrNum($name,'HomeModeAbsentBelatedTime',0));
        CommandDelete(undef,"atTmp_absent_belated_$name") if (ID("atTmp_absent_belated_$name",'at'));
        CommandDefine(undef,"atTmp_absent_belated_$name at +$hour {FHEM::Automation::HOMEMODE::execCMDs_belated(\"$name\",\"HomeCMDmode-absent-belated\",\"$option\")}");
      }
    }
    ContactOpenWarningAfterModeChange($hash,$option,$mode) if ($hash->{SENSORSCONTACT} && $option && $mode ne $option);
    push @commands,AttrVal($name,'HomeCMDmode','') if ($mode && AttrVal($name,'HomeCMDmode',undef));
    push @commands,AttrVal($name,'HomeCMDmode-'.makeReadingName($option),'') if (AttrVal($name,'HomeCMDmode-'.makeReadingName($option),undef));
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,$cmd,$option);
    readingsBulkUpdate($hash,'prevMode',$mode);
    readingsBulkUpdateIfChanged($hash,'presence',$present);
    readingsBulkUpdate($hash,'state',$option);
    readingsEndUpdate($hash,1);
    CommandSet(undef,"$name:FILTER=location!=$location location $location");
    if (AttrNum($name,'HomeAutoAlarmModes',1))
    {
      CommandDelete(undef,"atTmp_modeAlarm_delayed_arm_$name") if (ID("atTmp_modeAlarm_delayed_arm_$name",'at'));
      CommandSet(undef,"$name:FILTER=modeAlarm!=$namode modeAlarm $namode");
    }
  }
  elsif ($cmd eq 'modeAlarm-for-minutes')
  {
    $text = $langDE?
      "$cmd benötigt zwei Parameter: einen modeAlarm und die Minuten":
      "$cmd needs two paramters: a modeAlarm and minutes";
    return $text if (!$option || !$value);
    my $timer = "atTmp_alarmMode_for_timer_$name";
    my $time = hourMaker($value);
    CommandDelete(undef,$timer) if (ID($timer,'at'));
    CommandDefine(undef,"$timer at +$time set $name:FILTER=modeAlarm!=$amode modeAlarm $amode");
    CommandSet(undef,"$name:FILTER=modeAlarm!=$option modeAlarm $option");
  }
  elsif ($cmd eq 'dnd-for-minutes')
  {
    $text = $langDE?
      "$cmd benötigt einen Paramter: Minuten":
      "$cmd needs one paramter: minutes";
    return $text if (!$option);
    $text = $langDE?
      "$name darf nicht im dnd Modus sein um diesen Modus für bestimmte Minuten zu setzen! Bitte deaktiviere den dnd Modus zuerst!":
      "$name can't be in dnd mode to turn dnd on for minutes! Please disable dnd mode first!";
    return $text if (ReadingsVal($name,'dnd','off') eq 'on');
    my $timer = "atTmp_dnd_for_timer_$name";
    my $time = hourMaker($option);
    CommandDelete(undef,$timer) if (ID($timer,'at'));
    CommandDefine(undef,"$timer at +$time set $name:FILTER=dnd!=off dnd off");
    CommandSet(undef,"$name:FILTER=dnd!=on dnd on");
  }
  elsif ($cmd eq 'dnd')
  {
    push @commands,AttrVal($name,'HomeCMDdnd','') if (AttrVal($name,'HomeCMDdnd',undef));
    push @commands,AttrVal($name,"HomeCMDdnd-$option",'') if (AttrVal($name,"HomeCMDdnd-$option",undef));
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,$cmd,$option);
    readingsBulkUpdate($hash,'state','dnd') if ($option eq 'on');
    readingsBulkUpdate($hash,'state',$mode) if ($option ne 'on');
    readingsEndUpdate($hash,1);
  }
  elsif ($cmd eq 'location')
  {
    Log3 $name,4,"$name: Set location: $option";
    push @commands,AttrVal($name,'HomeCMDlocation','') if (AttrVal($name,'HomeCMDlocation',undef));
    push @commands,AttrVal($name,'HomeCMDlocation-'.makeReadingName($option),'') if (AttrVal($name,'HomeCMDlocation-'.makeReadingName($option),undef));
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,'prevLocation',$plocation);
    readingsBulkUpdate($hash,$cmd,$option);
    readingsEndUpdate($hash,1);
  }
  elsif ($cmd eq 'modeAlarm')
  {
    CommandDelete(undef,"atTmp_modeAlarm_delayed_arm_$name") if (ID("atTmp_modeAlarm_delayed_arm_$name",'at'));
    my $delay;
    if ($option =~ /^arm/x && AttrVal($name,'HomeModeAlarmArmDelay',0))
    {
      my @delays = split ' ',AttrVal($name,'HomeModeAlarmArmDelay',0);
      if (defined $delays[1])
      {
        $delay = $delays[0] if ($option eq 'armaway');
        $delay = $delays[1] if ($option eq 'armnight');
        $delay = $delays[2] if ($option eq 'armhome');
      }
      else
      {
        $delay = $delays[0];
      }
    }
    if ($delay)
    {
      my $hours = hourMaker(sprintf('%.2f',$delay / 60));
      CommandDefine(undef,"atTmp_modeAlarm_delayed_arm_$name at +$hours {FHEM::Automation::HOMEMODE::set_modeAlarm(\"$name\",\"$option\",\"$amode\")}");
    }
    else
    {
      set_modeAlarm($name,$option,$amode);
    }
  }
  elsif ($cmd eq 'anyoneElseAtHome')
  {
    $text = $langDE?
      "Zulässige Werte für $cmd sind nur on/off gefolgt von einem optionalen einzigartigem Namen!":
      "Values for $cmd can only be on/off with optional subsequent unique name!";
    return $text if ($option !~ /^(on|off)$/x);
    return $text if (defined($value) && $value !~ /^[\w\d-]+$/x);
    if (!defined($value))
    {
      push @commands,AttrVal($name,'HomeCMDanyoneElseAtHome','') if (AttrVal($name,'HomeCMDanyoneElseAtHome',undef));
      push @commands,AttrVal($name,"HomeCMDanyoneElseAtHome-$option",'') if (AttrVal($name,"HomeCMDanyoneElseAtHome-$option",undef));
      if (AttrNum($name,'HomeAutoAlarmModes',1))
      {
        CommandSet(undef,"$name:FILTER=modeAlarm=armaway modeAlarm armhome") if ($option eq 'on');
        CommandSet(undef,"$name:FILTER=modeAlarm=armhome modeAlarm armaway") if ($option eq 'off');
      }
      readingsSingleUpdate($hash,'anyoneElseAtHome',$option,1);
    }
    else
    {
      my $aeh = ReadingsVal($name,'anyoneElseAtHomeBy',undef)?ReadingsVal($name,'anyoneElseAtHomeBy',undef):ReadingsVal($name,'anyoneElseAtHome',undef) eq 'on'?$name:'none';
      my @arr;
      if ($option eq 'on')
      {
        if ($aeh ne 'none')
        {
          for my $item (split(/,/x,$aeh))
          {
            push @arr,$item;
          }
        }
        push @arr,$value;
        @arr = uniq @arr;
        my $ret = join(',',sort @arr);
        readingsSingleUpdate($hash,'anyoneElseAtHomeBy',$ret,1) if ($ret ne $aeh);
        CommandSet(undef,"$name:FILTER=anyoneElseAtHome!=on anyoneElseAtHome on");
      }
      else
      {
        return if ($aeh eq 'none' || $value eq 'none');
        for my $item (split /,/x,$aeh)
        {
          next if ($item eq $value);
          push @arr,$item;
        }
        @arr = uniq @arr;
        my $ret = int(@arr) ? join(',',sort @arr) : 'none';
        readingsSingleUpdate($hash,'anyoneElseAtHomeBy',$ret,1) if ($ret ne $aeh);
        CommandSet(undef,"$name:FILTER=anyoneElseAtHome!=off anyoneElseAtHome off") if ($ret eq 'none');
      }
      return;
    }
  }
  elsif ($cmd eq 'panic')
  {
    $text = $langDE?
      "Zulässige Werte für $cmd sind nur on oder off!":
      "Values for $cmd can only be on or off!";
    return $text if ($option !~ /^(on|off)$/x);
    push @commands,AttrVal($name,'HomeCMDpanic','') if (AttrVal($name,'HomeCMDpanic',undef));
    push @commands,AttrVal($name,"HomeCMDpanic-$option",'') if (AttrVal($name,"HomeCMDpanic-$option",undef));
    readingsSingleUpdate($hash,'panic',$option,1);
  }
  elsif ($cmd =~ /^device(Dis|En)able$/x)
  {
    ToggleDevice($hash,$option)
      if (($1 eq 'En' && grep {$_ eq $option} split /,/x,ReadingsVal($name,'devicesDisabled',''))
          || ($1 eq 'Dis' && grep {$_ eq $option} split /,/x,$hash->{helper}{enabledDevices}));
  }
  elsif ($cmd eq 'updateInternalsForce')
  {
    updateInternals($hash,1,1);
  }
  elsif ($cmd eq 'updateHomebridgeMapping')
  {
    HomebridgeMapping($hash);
  }
  elsif ($cmd eq 'updateSensorsUserattr')
  {
    addSensorsUserAttr($hash,$hash->{NOTIFYDEV},$hash->{NOTIFYDEV});
    return;
  }
  execCMDs($hash,serializeCMD($hash,@commands)) if (@commands);
  return;
}

sub set_modeAlarm
{
  my ($name,$option,$amode) = @_;
  my $hash = $defs{$name};
  my $resident = $hash->{helper}{lar} ? $hash->{helper}{lar} : ReadingsVal($name,'lastActivityByResident','');
  delete $hash->{helper}{lar} if ($hash->{helper}{lar});
  my @commands;
  push @commands,AttrVal($name,'HomeCMDmodeAlarm','') if (AttrVal($name,'HomeCMDmodeAlarm',undef));
  push @commands,AttrVal($name,"HomeCMDmodeAlarm-$option",'') if (AttrVal($name,"HomeCMDmodeAlarm-$option",undef));
  if ($option eq 'confirm')
  {
    CommandDefine(undef,"atTmp_modeAlarm_confirm_$name at +00:00:30 setreading $name:FILTER=alarmState=confirmed alarmState $amode");
    readingsSingleUpdate($hash,'alarmState',$option.'ed',1);
    execCMDs($hash,serializeCMD($hash,@commands),$resident) if (@commands);
  }
  else
  {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,'prevModeAlarm',$amode);
    readingsBulkUpdate($hash,'modeAlarm',$option);
    readingsBulkUpdateIfChanged($hash,'alarmState',$option);
    readingsEndUpdate($hash,1);
    TriggerState($hash) if ($hash->{SENSORSCONTACT} || $hash->{SENSORSMOTION});
    execCMDs($hash,serializeCMD($hash,@commands),$resident) if (@commands);
  }
  return;
}

sub execCMDs_belated
{
  my ($name,$attrib,$option) = @_;
  return if (!AttrVal($name,$attrib,undef) || ReadingsVal($name,'mode','') ne $option);
  my $hash = $defs{$name};
  my @commands;
  push @commands,AttrVal($name,$attrib,'');
  execCMDs($hash,serializeCMD($hash,@commands)) if (@commands);
  return;
}

sub alarmTriggered
{
  my ($hash,@triggers) = @_;
  my $name = $hash->{NAME};
  my @commands;
  my $text = makeHR($hash,0,@triggers);
  push @commands,AttrVal($name,'HomeCMDalarmTriggered','') if (AttrVal($name,'HomeCMDalarmTriggered',undef));
  readingsBeginUpdate($hash);
  readingsBulkUpdateIfChanged($hash,'alarmTriggered_ct',int(@triggers));
  if ($text)
  {
    push @commands,AttrVal($name,'HomeCMDalarmTriggered-on','') if (AttrVal($name,'HomeCMDalarmTriggered-on',undef));
    readingsBulkUpdateIfChanged($hash,'alarmTriggered',join ',',@triggers);
    readingsBulkUpdateIfChanged($hash,'alarmTriggered_hr',$text);
    readingsBulkUpdateIfChanged($hash,'alarmState','alarm');
  }
  else
  {
    push @commands,AttrVal($name,'HomeCMDalarmTriggered-off','') if (AttrVal($name,'HomeCMDalarmTriggered-off',undef) && ReadingsVal($name,'alarmTriggered',''));
    readingsBulkUpdateIfChanged($hash,'alarmTriggered','');
    readingsBulkUpdateIfChanged($hash,'alarmTriggered_hr','');
    readingsBulkUpdateIfChanged($hash,'alarmState',ReadingsVal($name,'modeAlarm','disarm'));
  }
  readingsEndUpdate($hash,1);
  execCMDs($hash,serializeCMD($hash,@commands)) if (@commands && ReadingsAge($name,'modeAlarm','') > 5);
  return;
}

sub makeHR
{
  my ($hash,$noart,@names) = @_;
  my $name = $hash->{NAME};
  my @aliases;
  my $and = (split /\|/x,AttrVal($name,'HomeTextAndAreIs','and|are|is'))[0];
  my $text;
  for (@names)
  {
    my $alias = $noart ? name2alias($_) : name2alias($_,1);
    push @aliases,$alias;
  }
  if (@aliases > 0)
  {
    my $alias = $aliases[0];
    $alias =~ s/^d/D/x;
    $text = $alias;
    if (@aliases > 1)
    {
      for (my $i = 1; $i < @aliases; $i++)
      {
        $text .= " $and " if ($i == int(@aliases) - 1);
        $text .= ', ' if ($i < @aliases - 1);
        $text .= $aliases[$i];
      }
    }
  }
  $text = $text ? $text : '';
  return $text;
}

sub RESIDENTS
{
  my ($hash,$dev) = @_;
  $dev = $hash->{DEF} if (!$dev);
  my $name = $hash->{NAME};
  my $events = deviceEvents($defs{$dev},1);
  my $devtype = $defs{$dev}->{TYPE};
  Log3 $name,5,"$name: RESIDENTS dev: $dev type: $devtype";
  my $lad = ReadingsVal($name,'lastActivityByResident','');
  my $mode;
  my $ema = ReplaceEventMap($dev,'absent',1);
  my $emp = ReplaceEventMap($dev,'present',1);
  if (grep {/^state:\s/} @{$events})
  {
    for my $evt (@{$events})
    {
      next unless ($evt =~ /^state:\s(.+)$/ && grep {$_ eq $1} split /,/x,$HOMEMODE_UserModesAll);
      $mode = $1;
      Log3 $name,4,"$name: RESIDENTS mode: $mode";
      last;
    }
  }
  if ($mode && $devtype eq 'RESIDENTS')
  {
    readingsSingleUpdate($hash,'lastActivityByResident',ReadingsVal($dev,'lastActivityByDev',''),1);
    $mode = $mode eq 'home' && AttrNum($name,'HomeAutoDaytime',1) ? DayTime($hash) : $mode;
    CommandSet(undef,"$name:FILTER=mode!=$mode mode $mode");
  }
  elsif ($devtype =~ /^ROOMMATE|GUEST|PET$/x)
  {
    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged($hash,'lastActivityByResident',$dev);
    readingsBulkUpdate($hash,'prevActivityByResident',$lad);
    readingsEndUpdate($hash,1);
    my @commands;
    if (grep {$_ eq 'wayhome: 1'} @{$events})
    {
      CommandSet(undef,"$name:FILTER=location!=wayhome location wayhome") if (ReadingsVal($name,'state','') =~ /^absent|gone$/x);
    }
    elsif (grep {$_ eq 'wayhome: 0'} @{$events})
    {
      my $rx = $hash->{RESIDENTS};
      $rx =~ s/,/|/xg;
      CommandSet(undef,"$name:FILTER=location!=underway location underway") if (ReadingsVal($name,'state','') =~ /^absent|gone$/x && !devspec2array("$rx:FILTER=wayhome=1"));
    }
    if (grep {$_ eq "presence: $ema"} @{$events})
    {
      Log3 $name,5,"$name: RESIDENTS dev: $dev - presence: $ema";
      readingsSingleUpdate($hash,'lastAbsentByResident',$dev,1);
      push @commands,AttrVal($name,'HomeCMDpresence-absent-resident','') if (AttrVal($name,'HomeCMDpresence-absent-resident',undef));
      push @commands,AttrVal($name,"HomeCMDpresence-absent-$dev",'') if (AttrVal($name,"HomeCMDpresence-absent-$dev",undef));
    }
    elsif (grep {$_ eq "presence: $emp"} @{$events})
    {
      Log3 $name,5,"$name: RESIDENTS dev: $dev - presence: $emp";
      readingsSingleUpdate($hash,'lastPresentByResident',$dev,1);
      push @commands,AttrVal($name,'HomeCMDpresence-present-resident','') if (AttrVal($name,'HomeCMDpresence-present-resident',undef));
      push @commands,AttrVal($name,"HomeCMDpresence-present-$dev",'') if (AttrVal($name,"HomeCMDpresence-present-$dev",undef));
    }
    if (grep {/^location:\s/} @{$events})
    {
      my $loc;
      for (@{$events})
      {
        Log3 $name,4,"$name: RESIDENTS dev: $dev - event: $_";
        next unless ($_ =~ /^location:\s(.+)$/);
        $loc = $1;
        last;
      }
      if ($loc)
      {
        Log3 $name,4,"$name: RESIDENTS dev: $dev - location: $loc";
        readingsSingleUpdate($hash,'lastLocationByResident',"$dev - $loc",1);
        push @commands,AttrVal($name,'HomeCMDlocation-resident','') if (AttrVal($name,'HomeCMDlocation-resident',undef));
        push @commands,AttrVal($name,'HomeCMDlocation-'.makeReadingName($loc).'-resident','') if (AttrVal($name,'HomeCMDlocation-'.makeReadingName($loc).'-resident',undef));
        push @commands,AttrVal($name,'HomeCMDlocation-'.makeReadingName($loc).'-'.$dev,'') if (AttrVal($name,'HomeCMDlocation-'.makeReadingName($loc).'-'.$dev,undef));
      }
    }
    if ($mode)
    {
      my $ls = ReadingsVal($dev,'lastState','');
      if ($mode =~ /^(home|awoken)$/x && AttrNum($name,'HomeAutoAwoken',0))
      {
        if ($mode eq 'home' && $ls eq 'asleep')
        {
          AnalyzeCommandChain(undef,"sleep 0.1; set $dev:FILTER=state!=awoken state awoken");
          return;
        }
        elsif ($mode eq 'awoken')
        {
          my $hours = hourMaker(AttrNum($name,'HomeAutoAwoken',0));
          CommandDelete(undef,'atTmp_awoken_'.$dev."_$name") if (ID('atTmp_awoken_'.$dev."_$name",'at'));
          CommandDefine(undef,'atTmp_awoken_'.$dev."_$name at +$hours set $dev:FILTER=state=awoken state home");
        }
      }
      if ($mode eq 'home' && $ls =~ /^absent|[gn]one$/x && AttrNum($name,'HomeAutoArrival',0))
      {
        my $hours = hourMaker(AttrNum($name,'HomeAutoArrival',0));
        AnalyzeCommandChain(undef,"sleep 0.1; set $dev:FILTER=location!=arrival location arrival");
        CommandDelete(undef,'atTmp_location_home_'.$dev."_$name") if (ID('atTmp_location_home_'.$dev."_$name",'at'));
        CommandDefine(undef,'atTmp_location_home_'.$dev."_$name at +$hours set $dev:FILTER=location=arrival location home");
      }
      elsif ($mode eq 'gotosleep' && AttrNum($name,'HomeAutoAsleep',0))
      {
        my $hours = hourMaker(AttrNum($name,'HomeAutoAsleep',0));
        CommandDelete(undef,'atTmp_asleep_'.$dev."_$name") if (ID('atTmp_asleep_'.$dev."_$name",'at'));
        CommandDefine(undef,'atTmp_asleep_'.$dev."_$name at +$hours set $dev:FILTER=state=gotosleep state asleep");
      }
      push @commands,AttrVal($name,"HomeCMDmode-$mode-resident",'') if (AttrVal($name,"HomeCMDmode-$mode-resident",undef));
      push @commands,AttrVal($name,"HomeCMDmode-$mode-$dev",'') if (AttrVal($name,"HomeCMDmode-$mode-$dev",undef));
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,'lastAsleepByResident',$dev) if ($mode eq 'asleep');
      readingsBulkUpdate($hash,'lastAwokenByResident',$dev) if ($mode eq 'awoken');
      readingsBulkUpdate($hash,'lastGoneByResident',$dev) if ($mode =~ /^[gn]one$/x);
      readingsBulkUpdate($hash,'lastGotosleepByResident',$dev) if ($mode eq 'gotosleep');
      readingsEndUpdate($hash,1);
      ContactOpenWarningAfterModeChange($hash,undef,undef,$dev);
    }
    if (@commands)
    {
      my $delay = AttrNum($name,'HomeResidentCmdDelay',1);
      my $cmd = encode_base64(serializeCMD($hash,@commands),'');
      InternalTimer(gettimeofday() + $delay,'FHEM::Automation::HOMEMODE::execUserCMDs',"$name|$cmd|$dev");
    }
  }
  return;
}

sub AttrList
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $adv = AttrCheck($hash,'HomeAdvancedAttributes',0);
  my @attribs = (
    'disable:1,0',
    'disabledForIntervals:textField',
    'HomeAdvancedDetails:none,detail,both,room',
    'HomeAdvancedAttributes:0,1',
    'HomeAutoAlarmModes:1,0',
    'HomeAutoArrival:textField',
    'HomeAutoAsleep:textField',
    'HomeAutoAwoken:textField',
    'HomeAutoDaytime:1,0',
    'HomeAutoPresence:0,1',
    'HomeCMDalarmTriggered',
    'HomeCMDalarmTriggered-off',
    'HomeCMDalarmTriggered-on',
    'HomeCMDanyoneElseAtHome',
    'HomeCMDanyoneElseAtHome-on',
    'HomeCMDanyoneElseAtHome-off',
    'HomeCMDdaytime',
    'HomeCMDdeviceDisable',
    'HomeCMDdeviceEnable',
    'HomeCMDdnd',
    'HomeCMDdnd-off',
    'HomeCMDdnd-on',
    'HomeCMDfhemDEFINED',
    'HomeCMDfhemINITIALIZED',
    'HomeCMDfhemSAVE',
    'HomeCMDfhemUPDATE',
    'HomeCMDlocation',
    'HomeCMDlocation-resident',
    'HomeCMDmode',
    'HomeCMDmode-absent-belated',
    'HomeCMDpanic',
    'HomeCMDpanic-on',
    'HomeCMDpanic-off',
    'HomeCMDpresence-absent',
    'HomeCMDpresence-present',
    'HomeCMDpresence-absent-resident',
    'HomeCMDpresence-present-resident',
    'HomeCMDpublic-ip-change',
    'HomeCMDseason',
    'HomeDaytimes',
    'HomeEventsDevices:textField',
    'HomeLanguage:EN,DE',
    'HomeModeAlarmArmDelay:textField',
    'HomeModeAbsentBelatedTime:textField',
    'HomeAtTmpRoom:textField',
    'HomePresenceDeviceType:textField',
    'HomePublicIpCheckInterval:textField',
    'HomeResidentCmdDelay:textField',
    'HomeSeasons',
    'HomeSensorAirpressure:textField',
    'HomeSensorHumidityOutside',
    'HomeSensorTemperatureOutside',
    'HomeSensorWindspeed:textField',
    'HomeSensorsAlarmDelay:textField',
    'HomeSensorsBattery:textField',
    'HomeSensorsBatteryReading:textField',
    'HomeSensorsContact:textField',
    'HomeSensorsContactReading:textField',
    'HomeSensorsLuminance:textField',
    'HomeSensorsLuminanceReading:textField',
    'HomeSensorsMotion:textField',
    'HomeSensorsMotionReading:textField',
    'HomeSensorsEnergy:textField',
    'HomeSensorsEnergyReading:textField',
    'HomeSensorsPower:textField',
    'HomeSensorsPowerReading:textField',
    'HomeSensorsSmoke:textField',
    'HomeSensorsSmokeReading:textField',
    'HomeSensorsTamper:textField',
    'HomeSensorsTamperReading:textField',
    'HomeSensorsWater:textField',
    'HomeSensorsWaterReading:textField',
    'HomeSpecialLocations:textField',
    'HomeSpecialModes:textField',
    'HomeTextAndAreIs:textField',
    'HomeTextTodayTomorrowAfterTomorrow:textField',
    'HomeTrendCalcAge:900,1800,2700,3600',
    'HomeTriggerAnyoneElseAtHome:textField',
    'HomeTriggerPanic:textField',
    'HomeTwilightDevice:textField',
    'HomeUWZ:textField',
    'HomeUserCSS',
    'HomeWeatherDevice:textField'
  );
  for (split /,/x,$HOMEMODE_Locations)
  {
    push @attribs,"HomeCMDlocation-$_";
  }
  for (split /,/x,$HOMEMODE_UserModesAll)
  {
    push @attribs,"HomeCMDmode-$_";
    push @attribs,"HomeCMDmode-$_-resident";
  }
  push @attribs,'HomeCMDmodeAlarm';
  for (split /,/x,$HOMEMODE_AlarmModes)
  {
    push @attribs,"HomeCMDmodeAlarm-$_";
  }
  if (AttrVal($name,'HomeAutoPresence',0))
  {
    push @attribs,'HomeAutoPresenceSuppressState:textField';
    push @attribs,'HomeCMDpresence-absent-device';
    push @attribs,'HomeCMDpresence-present-device';
  }
  if ($hash->{SENSORSSMOKE})
  {
    push @attribs,'HomeCMDalarmSmoke';
    push @attribs,'HomeCMDalarmSmoke-on';
    push @attribs,'HomeCMDalarmSmoke-off';
    push @attribs,'HomeSensorsSmokeValues:textField';
    push @attribs,'HomeTextNoSmokeSmoke:textField';
  }
  if ($hash->{SENSORSTAMPER})
  {
    push @attribs,'HomeCMDalarmTampered';
    push @attribs,'HomeCMDalarmTampered-on';
    push @attribs,'HomeCMDalarmTampered-off';
    push @attribs,'HomeSensorsTamperValues:textField';
    push @attribs,'HomeTextNoTamperTamper:textField';
  }
  if ($hash->{SENSORSBATTERY})
  {
    push @attribs,'HomeCMDbattery';
    push @attribs,'HomeCMDbatteryLow';
    push @attribs,'HomeCMDbatteryNormal';
    push @attribs,'HomeSensorsBatteryLowPercentage:textField';
  }  
  if ($hash->{SENSORSCONTACT})
  {
    push @attribs,'HomeCMDcontact';
    push @attribs,'HomeCMDcontactClosed';
    push @attribs,'HomeCMDcontactOpen';
    push @attribs,'HomeCMDcontactDoormain';
    push @attribs,'HomeCMDcontactDoormainClosed';
    push @attribs,'HomeCMDcontactDoormainOpen';
    push @attribs,'HomeCMDcontactOpenWarning1';
    push @attribs,'HomeCMDcontactOpenWarning2';
    push @attribs,'HomeCMDcontactOpenWarningLast';
    push @attribs,'HomeSensorsContactValues:textField';
    push @attribs,'HomeSensorsContactOpenTimeDividers:textField';
    push @attribs,'HomeSensorsContactOpenTimeMin:textField';
    push @attribs,'HomeSensorsContactOpenTimes:textField';
    push @attribs,'HomeSensorsContactOpenWarningUnified:0,1';
    push @attribs,'HomeTextClosedOpen:textField';
  }
  if (AttrVal($name,'HomeSensorTemperatureOutside',undef) || AttrVal($name,'HomeWeatherDevice',undef))
  {
    push @attribs,'HomeCMDicewarning';
    push @attribs,'HomeCMDicewarning-on';
    push @attribs,'HomeCMDicewarning-off';
    push @attribs,'HomeIcewarningOnOffTemps:textField';
  }
  if (AttrVal($name,'HomeWeatherDevice',undef))
  {
    push @attribs,'HomeTextWeatherForecastToday';
    push @attribs,'HomeTextWeatherForecastTomorrow';
    push @attribs,'HomeTextWeatherForecastInSpecDays';
    push @attribs,'HomeTextWeatherNoForecast';
    push @attribs,'HomeTextWeatherLong';
    push @attribs,'HomeTextWeatherShort';
    push @attribs,'HomeTextRisingConstantFalling:textField';
  }
  if ($hash->{SENSORSMOTION})
  {
    push @attribs,'HomeCMDmotion';
    push @attribs,'HomeCMDmotion-on';
    push @attribs,'HomeCMDmotion-off';
    push @attribs,'HomeSensorsMotionValues:textField';
    push @attribs,'HomeTextClosedOpen:textField';
  }
  if (AttrVal($name,'HomeTwilightDevice',undef))
  {
    push @attribs,'HomeCMDtwilight';
    push @attribs,'HomeCMDtwilight-sr';
    push @attribs,'HomeCMDtwilight-sr_astro';
    push @attribs,'HomeCMDtwilight-sr_civil';
    push @attribs,'HomeCMDtwilight-sr_indoor';
    push @attribs,'HomeCMDtwilight-sr_naut';
    push @attribs,'HomeCMDtwilight-sr_weather';
    push @attribs,'HomeCMDtwilight-ss';
    push @attribs,'HomeCMDtwilight-ss_astro';
    push @attribs,'HomeCMDtwilight-ss_civil';
    push @attribs,'HomeCMDtwilight-ss_indoor';
    push @attribs,'HomeCMDtwilight-ss_naut';
    push @attribs,'HomeCMDtwilight-ss_weather';
  }
  if ($hash->{SENSORSENERGY})
  {
    push @attribs,'HomeSensorsEnergyDivider:textField';
  }
  if ($hash->{SENSORSPOWER})
  {
    push @attribs,'HomeSensorsPowerDivider:textField';
  }
  if ($hash->{SENSORSLIGHT})
  {
    push @attribs,'HomeSensorsLuminanceDivider:textField';
  }
  if ($hash->{SENSORSWATER})
  {
    push @attribs,'HomeCMDalarmWater';
    push @attribs,'HomeCMDalarmWater-on';
    push @attribs,'HomeCMDalarmWater-off';
    push @attribs,'HomeSensorsWaterValues:textField';
    push @attribs,'HomeTextNoWaterWater:textField';
  }
  if (AttrVal($name,'HomeUWZ',undef))
  {
    push @attribs,'HomeCMDuwz-warn';
    push @attribs,'HomeCMDuwz-warn-begin';
    push @attribs,'HomeCMDuwz-warn-end';
  }
  for (split /,/x,AttrCheck($hash,'HomeSpecialModes'))
  {
    push @attribs,'HomeCMDmode-'.makeReadingName($_);
  }
  for (split /,/x,AttrCheck($hash,'HomeSpecialLocations'))
  {
    push @attribs,'HomeCMDlocation-'.makeReadingName($_);
  }
  if (InternalVal($name,'CALENDARS',''))
  {
    push @attribs,'HomeCMDevent';
    for my $cal (devspec2array(InternalVal($name,'CALENDARS','')))
    {
      my $evts = CalendarEvents($name,$cal);
      push @attribs,'HomeEventsFilter-'.$cal.':textField';
      push @attribs,"HomeCMDevent-$cal-each";
      if ($adv)
      {
        for my $evt (@{$evts})
        {
          push @attribs,"HomeCMDevent-$cal-".makeReadingName($evt).'-begin';
          push @attribs,"HomeCMDevent-$cal-".makeReadingName($evt).'-end';
        }
      }
    }
  }
  for my $resident (split /,/x,$hash->{RESIDENTS})
  {
    my $devtype = ID($resident,'ROOMMATE|GUEST|PET') ? $defs{$resident}->{TYPE} : '';
    next unless ($devtype);
    if ($adv)
    {
      my $states = 'absent';
      $states .= ",$HOMEMODE_UserModesAll" if ($devtype =~ /^ROOMMATE|PET$/x);
      $states .= ",home,$HOMEMODE_UserModes" if ($devtype eq 'GUEST');
      for (split /,/x,$states)
      {
        push @attribs,"HomeCMDmode-$_-$resident";
      }
      push @attribs,"HomeCMDpresence-absent-$resident";
      push @attribs,"HomeCMDpresence-present-$resident";
      my $locs = $devtype eq 'ROOMMATE' ? AttrVal($resident,'rr_locations','') : $devtype eq 'GUEST' ? AttrVal($resident,'rg_locations','') : AttrVal($resident,'rp_locations','');
      for (split/,/x,$locs)
      {
        my $loc = makeReadingName($_);
        push @attribs,'HomeCMDlocation-'.$loc.'-'.$resident;
        push @attribs,'HomeCMDlocation-'.$loc.'-resident';
      }
    }
    my @presdevs = $hash->{helper}{presdevs}{$resident}?@{$hash->{helper}{presdevs}{$resident}}:();
    if (@presdevs)
    {
      my $count = 0;
      my $numbers = '';
      for (@presdevs)
      {
        $count++;
        $numbers .= ',' if ($numbers);
        $numbers .= $count;
      }
      push @attribs,"HomePresenceDeviceAbsentCount-$resident:$numbers";
      push @attribs,"HomePresenceDevicePresentCount-$resident:$numbers";
      if ($adv)
      {
        for (@presdevs)
        {
          push @attribs,"HomeCMDpresence-absent-$resident-device";
          push @attribs,"HomeCMDpresence-present-$resident-device";
          push @attribs,"HomeCMDpresence-absent-$resident-$_";
          push @attribs,"HomeCMDpresence-present-$resident-$_";
        }
      }
    }
  }
  for (split ' ',AttrCheck($hash,'HomeDaytimes',$HOMEMODE_Daytimes))
  {
    my $text = makeReadingName((split /\|/x)[1]);
    my $d = "HomeCMDdaytime-$text";
    my $m = "HomeCMDmode-$text";
    push @attribs,$d;
    push @attribs,$m;
  }
  for (split ' ',AttrCheck($hash,'HomeSeasons',$HOMEMODE_Seasons))
  {
    my $text = (split /\|/x)[1];
    my $s = 'HomeCMDseason-'.makeReadingName($text);
    push @attribs,$s;
  }
  my @list;
  for my $attrib (@attribs)
  {
    $attrib = $attrib =~ /^.+:.+$/x ? $attrib : "$attrib:textField-long";
    push @list,$attrib;
  }
  @list = uniq sort @list;
  my $ret = join(' ',@list);
  $hash->{'.AttrList'} = "$ret $readingFnAttributes";
  #######################
  # for compatibiliy reasons: clean & delete userattr if possible
  my $ua = AttrVal($name,'userattr',undef);
  if ($ua)
  {
    my @stayattr;
    for (split ' ',$ua)
    {
      # cleaning
      if ($_ !~ /^Home/x)
      {
        push @stayattr,$_;
      }
    }
    if (int(@stayattr))
    {
      CommandAttr(undef,"$name userattr ".join ' ',sort @stayattr);
    }
    else
    {
      CommandDeleteAttr(undef,"$name userattr");
    }
  }
  #######################
  return;
}

sub cleanUserattr
{
  my ($hash,$devs,$newdevs) = @_;
  my $name = $hash->{NAME};
  my @devspec = devspec2array($devs);
  return if (!@devspec);
  my @newdevspec = $newdevs?devspec2array($newdevs):();
  for my $dev (@devspec)
  {
    my $ua = AttrVal($dev,'userattr','');
    next if (!$ua);
    my @stayattr;
    for my $attr (split ' ',$ua)
    {
      if ($attr =~ /^Home/x)
      {
        $attr =~ s/:.*$//x;
        CommandDeleteAttr(undef,"$dev $attr") if ((AttrVal($dev,$attr,'') && !@newdevspec) || (AttrVal($dev,$attr,'') && @newdevspec && !grep {$_ eq $dev} @newdevspec));
        next;
      }
      push @stayattr,$attr;
    }
    if (@stayattr)
    {
      my $list = join(' ',uniq sort @stayattr);
      CommandAttr(undef,"$dev userattr $list");
    }
    else
    {
      CommandDeleteAttr(undef,"$dev userattr");
    }
  }
  return;
}

sub Attr
{
  my ($cmd,$name,$attr_name,$attr_value) = @_;
  my $hash = $defs{$name};
  return if (!$init_done || ReadingsNum($name,'.HOMEMODE_ver',1.5) < 1.6);
  delete $hash->{helper}{lastChangedAttr};
  delete $hash->{helper}{lastChangedAttrValue};
  my $attr_value_old = AttrVal($name,$attr_name,'');
  $hash->{helper}{lastChangedAttr} = $attr_name;
  my $text;
  if ($cmd eq 'set')
  {
    $hash->{helper}{lastChangedAttrValue} = $attr_value;
    if ($attr_name =~ /^(HomeAutoAwoken|HomeAutoAsleep|HomeAutoArrival|HomeModeAbsentBelatedTime)$/x)
    {
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Muss eine Zahl von 0 bis 6000 sein.":
        "Invalid value $attr_value for attribute $attr_name. Must be a number from 0 to 6000.";
      return $text if ($attr_value !~ /^(\d{1,4})(\.\d{1,2})?$/x || $1 > 6000 || $1 < 0);
    }
    elsif ($attr_name eq 'HomeLanguage')
    {
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Kann nur \"EN\" oder \"DE\" sein, Vorgabewert ist Sprache aus global.":
        "Invalid value $attr_value for attribute $attr_name. Must be \"EN\" or \"DE\", default is language from global.";
      return $text if ($attr_value !~ /^(DE|EN)$/x);
      $langDE = $attr_value eq 'DE'?1:0;
    }
    elsif ($attr_name eq 'HomeAdvancedDetails')
    {
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Kann nur \"none\", \"detail\", \"both\" oder \"room\" sein, Vorgabewert ist \"none\".":
        "Invalid value $attr_value for attribute $attr_name. Must be \"none\", \"detail\", \"both\" or \"room\", default is \"none\".";
      return $text if ($attr_value !~ /^(none|detail|both|room)$/x);
      if ($attr_value eq 'detail')
      {
        $modules{HOMEMODE}->{FW_deviceOverview} = 1;
        $modules{HOMEMODE}->{FW_addDetailToSummary} = 0;
      }
      else
      {
        $modules{HOMEMODE}->{FW_deviceOverview} = 1;
        $modules{HOMEMODE}->{FW_addDetailToSummary} = 1;
      }
    }
    elsif ($attr_name =~ /^(disable|HomeAdvancedAttributes|HomeAutoDaytime|HomeAutoAlarmModes|HomeAutoPresence|HomeSensorsContactOpenWarningUnified)$/x)
    {
      my $n = $attr_name eq 'HomeAutoAlarmModes'?1:0;
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Kann nur 1 oder 0 sein, Vorgabewert ist $n.":
        "Invalid value $attr_value for attribute $attr_name. Must be 1 or 0, default is $n.";
      return $text if ($attr_value !~ /^[01]$/x);
      RemoveInternalTimer($hash) if ($attr_name eq 'disable' && $attr_value);
      GetUpdate($hash) if ($attr_name eq 'disable' && !$attr_value);
      updateInternals($hash) if ($attr_name =~ /^Home(AdvancedAttributes|AutoPresence)$/x && $init_done);
      addSensorsUserAttr($hash,$hash->{SENSORSCONTACT},$hash->{SENSORSCONTACT}) if ($attr_name eq 'HomeSensorsContactOpenWarningUnified' && $init_done);
    }
    elsif ($attr_name =~ /^HomeCMD/x && $init_done)
    {
      if ($attr_value_old ne $attr_value)
      {
        my $err = perlSyntaxCheck(replacePlaceholders($hash,$attr_value));
        return $err if ($err);
      }
    }
    elsif ($attr_name =~ /^HomeAutoPresenceSuppressState$/x && $init_done)
    {
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Es wird wenigstens ein Wert oder maximal 3 Pipe separierte Werte benötigt! z.B. asleep|gotosleep":
        "Invalid value $attr_value for attribute $attr_name. You have to provide at least one value or max 3 values pipe separated, e.g. asleep|gotosleep";
      return $text if ($attr_value !~ /^(asleep|gotosleep|awoken)(\|(asleep|gotosleep|awoken)){0,2}$/x);
    }
    elsif ($attr_name =~ /^HomeEventsDevices$/x && $init_done)
    {
      my $d = devspec2array($attr_value);
      if ($d eq $attr_value)
      {
        $text = $langDE?
          'Keine gültigen Calendar/holiday Geräte gefunden in devspec "'.$attr_value.'"':
          'No valid Calendar/holiday device(s) found in devspec "'.$attr_value.'"';
        return $text;
      }
      else
      {
        updateInternals($hash,1);
      }
    }
    elsif ($attr_name =~ /^HomeEventsFilter-.+$/x && $init_done)
    {
      updateInternals($hash);
    }
    elsif ($attr_name =~ /^(HomePresenceDeviceType)$/x && $init_done)
    {
      $text = $langDE?
        "$attr_value muss ein gültiger TYPE sein":
        "$attr_value must be a valid TYPE";
      return $text if (!CheckIfIsValidDevspec($name,"TYPE=$attr_value",'presence'));
      updateInternals($hash);
    }
    elsif ($attr_name =~ /^HomeSensors(Contact|Battery|Energy|Luminance|Motion|Power|Smoke|Tamper|Water)Reading$/x)
    {
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Es wird ein einzelnes Reading benötigt! z.B. state":
        "Invalid value $attr_value for attribute $attr_name. You have to provide one reading, e.g. state";
      return $text if ($attr_value !~ /^[\w\-\.]+$/x);
    }
    elsif ($attr_name =~ /^HomeSensors(Contact|Motion|Smoke|Tamper|Water)Values$/x)
    {
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Es wird wenigstens ein Wert oder mehrere Pipe separierte Werte benötigt! z.B. open|tilted|on":
        "Invalid value $attr_value for attribute $attr_name. You have to provide at least one value or more values pipe separated, e.g. open|tilted|on";
      return $text if ($attr_value !~ /^[\w\-\+\*\.\(\)]+(\|[\w\-\+\*\.\(\)]+){0,}$/xi);
    }
    elsif ($attr_name eq 'HomeIcewarningOnOffTemps')
    {
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Es werden 2 Leerzeichen separierte Temperaturen benötigt, z.B. -0.1 2.5":
        "Invalid value $attr_value for attribute $attr_name. You have to provide 2 space separated temperatures, e.g. -0.1 2.5";
      return $text if ($attr_value !~ /^-?\d{1,2}(\.\d)?\s-?\d{1,2}(\.\d)?$/);
    }
    elsif ($attr_name eq 'HomeSensorsContactOpenTimeDividers')
    {
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Es werden Leerzeichen separierte Zahlen für jede Jahreszeit (aus Attribut HomeSeasons) benötigt, z.B. 2 1 2 3.333":
        "Invalid value $attr_value for attribute $attr_name. You have to provide space separated numbers for each season in order of the seasons provided in attribute HomeSeasons, e.g. 2 1 2 3.333";
      return $text if ($attr_value !~ /^\d{1,2}(\.\d{1,3})?(\s\d{1,2}(\.\d{1,3})?){0,}$/);
      my @times = split ' ',$attr_value;
      my $s = int(split ' ',AttrVal($name,'HomeSeasons',$HOMEMODE_Seasons));
      my $t = int(@times);
      $text = $langDE?
        "Anzahl von $attr_name Werten ($t) ungleich zu den verfügbaren Jahreszeiten ($s) im Attribut HomeSeasons!":
        "Number of $attr_name values ($t) not matching the number of available seasons ($s) in attribute HomeSeasons!";
      return $text if ($s != $t);
      for (@times)
      {
        $text = $langDE?
          'Teiler dürfen nicht 0 sein, denn Division durch 0 ist nicht definiert!':
          'Dividers can´t be zero, because division by zero is not defined!';
        return $text if ($_ == 0);
      }
    }
    elsif ($attr_name eq 'HomeSensorsContactOpenTimeMin')
    {
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Zahlen von 1 bis 9.9 sind nur erlaubt!":
        "Invalid value $attr_value for attribute $attr_name. Numbers from 1 to 9.9 are allowed only!";
      return $text if ($attr_value !~ /^[1-9](\.\d)?$/x);
    }
    elsif ($attr_name eq 'HomeSensorsContactOpenTimes')
    {
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Es werden Leerzeichen separierte Zahlen benötigt, z.B. 5 10 15 17.5":
        "Invalid value $attr_value for attribute $attr_name. You have to provide space separated numbers, e.g. 5 10 15 17.5";
      return $text if ($attr_value !~ /^\d{1,4}(\.\d)?((\s\d{1,4}(\.\d)?)?){0,}$/);
      for (split ' ',$attr_value)
      {
        $text = $langDE?
          'Teiler dürfen nicht 0 sein, denn Division durch 0 ist nicht definiert!':
          'Dividers can´t be zero, because division by zero is not defined!';
        return $text if ($_ == 0);
      }
    }
    elsif ($attr_name =~ /^HomeSensors(Energy|Power)Divider$/x)
    {
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Es wird nur eine Zahl benötigt (auch negativ möglich um Wert umzukehren, z.B. PV-Anlage), z.B. 1000":
        "Invalid value $attr_value for attribute $attr_name. You have to provide a single number (even negativ numbers are valid to reverse the sign of a number), e.g. 1000";
      return $text if ($attr_value !~ /^-?\d{1,}(\.\d{1,})?$/);
    }
    elsif ($attr_name eq 'HomeResidentCmdDelay')
    {
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Zahlen von 0 bis 9999 sind nur erlaubt!":
        "Invalid value $attr_value for attribute $attr_name. Numbers from 0 to 9999 are allowed only!";
      return $text if ($attr_value !~ /^\d{1,4}$/x);
    }
    elsif ($attr_name =~ /^HomeSpecial(Modes|Locations)$/x && $init_done)
    {
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Muss eine Komma separierte Liste von Wörtern sein!":
        "Invalid value $attr_value for attribute $attr_name. Must be a comma separated list of words!";
      return $text if ($attr_value !~ /^[\w\-äöüß\.]+(,[\w\-äöüß\.]+){0,}$/xi);
      AttrList($hash);
    }
    elsif ($attr_name eq 'HomePublicIpCheckInterval')
    {
      $text = $langDE?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Muss eine Zahl von 1 bis 99999 für das Interval in Minuten sein!":
        "Invalid value $attr_value for attribute $attr_name. Must be a number from 1 to 99999 for interval in minutes!";
      return $text if ($attr_value !~ /^\d{1,5}$/x);
    }
    elsif ($attr_name =~ /^HomeSensors(Battery|Contact|Energy|Luminance|Motion|Power|Smoke|Tamper|Water)$/x && $init_done)
    {
      $text = $langDE?
        "$attr_value muss ein gültiger Devspec sein!":
        "$attr_value must be a valid devspec!";
      return $text if (!CheckIfIsValidDevspec($name,$attr_value));
      updateInternals($hash,1) if ($attr_value ne $attr_value_old);
    }
    elsif ($attr_name eq 'HomeSensorsPower' && $init_done)
    {
      my $p = AttrVal($name,'HomeSensorsPowerReading','power');
      $text = $langDE?
        "$attr_value muss ein gültiger Devspec mit '$p' Reading sein!":
        "$attr_value must be a valid devspec with '$p' reading!";
      return $text if (!CheckIfIsValidDevspec($name,$attr_value,$p));
      updateInternals($hash);
    }
    elsif ($attr_name eq 'HomeSensorsEnergy' && $init_done)
    {
      my $e = AttrVal($name,'HomeSensorsEnergyReading','energy');
      $text = $langDE?
        "$attr_value muss ein gültiger Devspec mit '$e' Readings sein!":
        "$attr_value must be a valid devspec with '$e' reading!";
      return $text if (!CheckIfIsValidDevspec($name,$attr_value,$e));
      updateInternals($hash);
    }
    elsif ($attr_name eq 'HomeTwilightDevice' && $init_done)
    {
      $text = $langDE?
        "$attr_value muss ein gültiges Gerät vom TYPE Twilight sein!":
        "$attr_value must be a valid device of TYPE Twilight!";
      return $text if (!CheckIfIsValidDevspec($name,"$attr_value:FILTER=TYPE=Twilight"));
      if ($attr_value_old ne $attr_value)
      {
        CommandDeleteReading(undef,"$name light|twilight|twilightEvent");
        updateInternals($hash);
      }
    }
    elsif ($attr_name eq 'HomeWeatherDevice' && $init_done)
    {
      $text = $langDE?
        "$attr_value muss ein gültiges Gerät vom TYPE Weather sein!":
        "$attr_value must be a valid device of TYPE Weather!";
      return $text if (!CheckIfIsValidDevspec($name,"$attr_value:FILTER=TYPE=Weather"));
      if ($attr_value_old ne $attr_value)
      {
        CommandDeleteReading(undef,"$name pressure") if (!AttrVal($name,'HomeSensorAirpressure',undef));
        CommandDeleteReading(undef,"$name wind") if (!AttrVal($name,'HomeSensorWindspeed',undef));
        CommandDeleteReading(undef,"$name temperature") if (!AttrVal($name,'HomeSensorTemperatureOutside',undef));
        CommandDeleteReading(undef,"$name humidity") if (!AttrVal($name,'HomeSensorHumidityOutside',undef));
        updateInternals($hash);
      }
    }
    elsif ($attr_name eq 'HomeSensorTemperatureOutside' && $init_done)
    {
      $text = $langDE?
        "$attr_value muss ein gültiger Devspec mit temperature Reading sein!":
        "$attr_value must be a valid device with temperature reading!";
      return $text if (!CheckIfIsValidDevspec($name,$attr_value,'temperature'));
      CommandDeleteAttr(undef,"$name HomeSensorHumidityOutside") if (AttrVal($name,'HomeSensorHumidityOutside',undef) && $attr_value eq AttrVal($name,'HomeSensorHumidityOutside',undef));
      if ($attr_value_old ne $attr_value)
      {
        CommandDeleteReading(undef,"$name temperature") if (!AttrVal($name,'HomeWeatherDevice',undef));
        updateInternals($hash);
      }
    }
    elsif ($attr_name eq 'HomeSensorHumidityOutside' && $init_done)
    {
      $text = $langDE?
        'Dieses Attribut ist wegzulassen wenn es den gleichen Wert haben sollte wie HomeSensorTemperatureOutside!':
        'You have to omit this attribute if it should have the same value like HomeSensorTemperatureOutside!';
      return $text if ($attr_value eq AttrVal($name,'HomeSensorTemperatureOutside',undef));
      $text = $langDE?
        "$attr_value muss ein gültiger Devspec mit humidity Reading sein!":
        "$attr_value must be a valid device with humidity reading!";
      return $text if (!CheckIfIsValidDevspec($name,$attr_value,'humidity'));
      if ($attr_value_old ne $attr_value)
      {
        CommandDeleteReading(undef,"$name humidity") if (!AttrVal($name,'HomeWeatherDevice',undef));
        updateInternals($hash);
      }
    }
    elsif ($attr_name eq 'HomeDaytimes' && $init_done)
    {
      $text = $langDE?
        "$attr_value für $attr_name muss eine Leerzeichen separierte Liste aus Uhrzeit|Text Paaren sein! z.B. $HOMEMODE_Daytimes":
        "$attr_value for $attr_name must be a space separated list of time|text pairs! e.g. $HOMEMODE_Daytimes";
      return $text if ($attr_value !~ /^([0-2]\d:[0-5]\d\|[\w\-äöüß\.]+)(\s[0-2]\d:[0-5]\d\|[\w\-äöüß\.]+){0,}$/i);
      if ($attr_value_old ne $attr_value)
      {
        my @ts;
        for (split ' ',$attr_value)
        {
          my $time = (split /\|/x)[0];
          my ($h,$m) = split /:/x,$time;
          my $minutes = $h * 60 + $m;
          my $lastminutes = @ts ? $ts[int(@ts)-1] : -1;
          if ($minutes > $lastminutes)
          {
            push @ts,$minutes;
          }
          else
          {
            $text = $langDE?
              "Falsche Reihenfolge der Zeiten in $attr_value":
              "Wrong times order in $attr_value";
            return $text;
          }
        }
        AttrList($hash);
      }
    }
    elsif ($attr_name eq 'HomeSeasons' && $init_done)
    {
      $text = $langDE?
        "$attr_value für $attr_name muss eine Leerzeichen separierte Liste aus Datum|Text Paaren mit mindestens 4 Werten sein! z.B. $HOMEMODE_Seasons":
        "$attr_value for $attr_name must be a space separated list of date|text pairs with at least 4 values! e.g. $HOMEMODE_Seasons";
      return $text if (int(split ' ',$attr_value) < 4 || int(split /\|/x,$attr_value) < 5);
      if ($attr_value_old ne $attr_value)
      {
        my @ds;
        for (split ' ',$attr_value)
        {
          my $time = (split /\|/x)[0];
          my ($m,$d) = split /\./x,$time;
          my $days = $m * 31 + $d;
          my $lastdays = @ds ? $ds[int(@ds) - 1] : -1;
          if ($days > $lastdays)
          {
            push @ds,$days;
          }
          else
          {
            $text = $langDE?
              "Falsche Reihenfolge der Datumsangaben in $attr_value":
              "Wrong dates order in $attr_value";
            return $text;
          }
        }
        AttrList($hash);
      }
    }
    elsif ($attr_name eq 'HomeModeAlarmArmDelay')
    {
      $text = $langDE?
        "$attr_value für $attr_name muss eine einzelne Zahl sein für die Verzögerung in Sekunden oder 3 Leerzeichen separierte Zeiten in Sekunden für jeden modeAlarm individuell (Reihenfolge: armaway armnight armhome), höhster Wert ist 99999":
        "$attr_value for $attr_name must be a single number for delay time in seconds or 3 space separated times in seconds for each modeAlarm individually (order: armaway armnight armhome), max. value is 99999";
      return $text if ($attr_value !~ /^(\d{1,5})((\s\d{1,5})(\s\d{1,5}))?$/);
    }
    elsif ($attr_name =~ /^(HomeTextAndAreIs|HomeTextTodayTomorrowAfterTomorrow|HomeTextRisingConstantFalling)$/x)
    {
      $text = $langDE?
        "$attr_value für $attr_name muss eine Pipe separierte Liste mit 3 Werten sein!":
        "$attr_value for $attr_name must be a pipe separated list with 3 values!";
      return $text if (int(split /\|/x,$attr_value) != 3);
    }
    elsif ($attr_name eq 'HomeTextClosedOpen')
    {
      $text = $langDE?
        "$attr_value für $attr_name muss eine Pipe separierte Liste mit 2 Werten sein!":
        "$attr_value for $attr_name must be a pipe separated list with 2 values!";
      return $text if (int(split /\|/x,$attr_value) != 2);
    }
    elsif ($attr_name eq 'HomeUWZ' && $init_done)
    {
      $text = $langDE?
        "$attr_value muss ein gültiges Gerät vom TYPE Weather sein!":
        "$attr_value must be a valid device of TYPE Weather!";
      return "$attr_value must be a valid device of TYPE UWZ!" if (!CheckIfIsValidDevspec($name,"$attr_value:FILTER=TYPE=UWZ"));
      updateInternals($hash) if ($attr_value_old ne $attr_value);
    }
    elsif ($attr_name eq 'HomeSensorsLuminance' && $init_done)
    {
      my $read = AttrVal($name,'HomeSensorsLuminanceReading','luminance');
      $text = $langDE?
        "$attr_value muss ein gültiges Gerät mit $read Reading sein!":
        "$attr_name must be a valid device with $read reading!";
      return $text if (!CheckIfIsValidDevspec($name,$attr_value,$read));
      updateInternals($hash);
    }
    elsif ($attr_name =~ /^HomeSensors(Battery|Contact|Energy|Luminance|Motion|Power|Smoke|Tamper|Water)Reading$/x && $init_done)
    {
      $text = $langDE?
        "$attr_name muss ein einzelnes gültiges Reading sein!":
        "$attr_name must be a single valid reading!";
      return $text if ($attr_value !~ /^([\w\-\.]+)$/x);
      updateInternals($hash) if ($attr_value_old ne $attr_value);
    }
    elsif ($attr_name =~ /^HomeSensor(Energy|Power)Divider$/x && $init_done)
    {
      $text = $langDE?
        "$attr_name muss ein einzelne Zahl, aber nicht 0 sein, z.B. 1000 oder 0.001!":
        "$attr_name must be a single number, but not 0, p.e. 1000 or 0.001!";
      return $text if ($attr_value !~ /^(?!0)\d+(\.\d+)?$/x || !CheckIfIsValidDevspec($name,$1,$2));
    }
    elsif ($attr_name =~ /^HomeSensorAirpressure|HomeSensorWindspeed$/x && $init_done)
    {
      $text = $langDE?
        "$attr_name muss ein einzelnes gültiges Gerät und Reading sein (Sensor:Reading)!":
        "$attr_name must be a single valid device and reading (sensor:reading)!";
      return $text if ($attr_value !~ /^([\w\.]+):([\w\-\.]+)$/x || !CheckIfIsValidDevspec($name,$1,$2));
      updateInternals($hash) if ($attr_value_old ne $attr_value);
    }
    elsif ($attr_name eq 'HomeSensorsAlarmDelay')
    {
      $text = $langDE?
        "$attr_name muss eine einzelne Zahl (in Sekunden) sein oder drei leerzeichengetrennte Zahlen (in Sekunden sein für jeden Alarm Modus individuell (armaway armhome armnight).":
        "$attr_name must be a single number (in seconds) or three space separated numbers (in seconds)<br>for each alarm mode individually (armaway armhome armnight).";
      return $text if ($attr_value !~ /^\d{1,3}((\s\d{1,3}){2})?$/);
    }
    elsif ($attr_name eq 'HomeSensorsBattery' && $init_done)
    {
      my $read = AttrVal($name,'HomeSensorsBatteryReading','battery');
      $text = $langDE?
        "$attr_name muss ein gültiges Gerät mit $read Reading sein!":
        "$attr_name must be a valid device with $read reading!";
      return $text if (!CheckIfIsValidDevspec($name,$attr_value,$read));
      updateInternals($hash);
    }
    elsif ($attr_name eq 'HomeSensorsBatteryLowPercentage')
    {
      $text = $langDE?
        "$attr_name muss ein Wert zwischen 0 und 99 sein!":
        "$attr_name must be a value from 0 to 99!";
      return $text if ($attr_value !~ /^\d{1,2}$/x);
      updateInternals($hash);
    }
    elsif ($attr_name eq 'HomeTriggerPanic' && $init_done)
    {
      $text = $langDE?
        "$attr_name muss ein gültiges Gerät, Reading und Wert in Form von \"Gerät:Reading:WertAn:WertAus\" (WertAus ist optional) sein!":
        "$attr_name must be a valid device, reading and value like \"device:reading:valueOn:valueOff\" (valueOff is optional)!";
      return $text if ($attr_value !~ /^([\w\.]+):([\w\.]+):[\w\-\.]+(:[\w\-\.]+)?$/x || !CheckIfIsValidDevspec($name,$1,$2));
      updateInternals($hash);
    }
    elsif ($attr_name eq 'HomeTriggerAnyoneElseAtHome' && $init_done)
    {
      $text = $langDE?
        "$attr_name muss ein gültiges Gerät, Reading und Wert in Form von \"Gerät:Reading:WertAn:WertAus\" sein!":
        "$attr_name must be a valid device, reading and value like \"device:reading:valueOn:valueOff\" !";
      return $text if ($attr_value !~ /^([\w\.]+):([\w\.]+):[\w\-\.]+(:[\w\-\.]+)$/x || !CheckIfIsValidDevspec($name,$1,$2));
      updateInternals($hash);
    }
    elsif ($attr_name eq 'HomeUserCSS' && $init_done)
    {
      $text = $langDE?
        "$attr_name muss gültiger CSS Code sein!":
        "$attr_name must be valid CSS code!";
      return $text if ($attr_value !~ /^[\.\w\#]+\{.+\}$/xmgis);
    }
  }
  else
  {
    $hash->{helper}{lastChangedAttrValue} = '---';
    if ($attr_name eq 'disable')
    {
      GetUpdate($hash);
    }
    elsif ($attr_name eq 'HomeLanguage')
    {
      $langDE = AttrVal('global','language','DE') ? 1 : undef;
    }
    elsif ($attr_name =~ /^(HomeAdvancedAttributes|HomeAutoPresence|HomePresenceDeviceType|HomeEventsDevices|HomeSensorAirpressure|HomeSensorWindspeed|HomeSensorsBattery|HomeSensorsBatteryReading)$/x)
    {
      CommandDeleteReading(undef,"$name event-.+") if ($attr_name =~ /^HomeEventsDevices$/x);
      CommandDeleteReading(undef,"$name battery.*|lastBatteryLow") if ($attr_name eq 'HomeSensorsBattery');
      updateInternals($hash);
    }
    elsif ($attr_name =~ /^HomeEventsFilter-.+$/x)
    {
      updateInternals($hash);
    }
    elsif ($attr_name eq 'HomeSensorsContactOpenWarningUnified')
    {
      addSensorsUserAttr($hash,$hash->{SENSORSCONTACT},$hash->{SENSORSCONTACT}) if ($init_done);
    }
    elsif ($attr_name =~ /^(HomeSensorsContact|HomeSensorsMotion)$/x)
    {
      my $olddevs = $hash->{SENSORSCONTACT};
      $olddevs = $hash->{SENSORSMOTION} if ($attr_name eq 'HomeSensorsMotion');
      my $read = 'lastContact|prevContact|contacts.*';
      $read = 'lastMotion|prevMotion|motions.*' if ($attr_name eq 'HomeSensorsMotion');
      CommandDeleteReading(undef,"$name $read");
      updateInternals($hash);
      cleanUserattr($hash,$olddevs);
    }
    elsif ($attr_name eq 'HomeSensorsSmoke')
    {
      CommandDeleteReading(undef,"$name alarmSmoke");
      updateInternals($hash);
    }
    elsif ($attr_name eq 'HomeSensorsEnergy')
    {
      CommandDeleteReading(undef,"$name energy");
      updateInternals($hash);
    }
    elsif ($attr_name eq 'HomeSensorsPower')
    {
      CommandDeleteReading(undef,"$name power");
      updateInternals($hash);
    }
    elsif ($attr_name eq 'HomePublicIpCheckInterval')
    {
      delete $hash->{'.IP_TRIGGERTIME_NEXT'};
    }
    elsif ($attr_name =~ /^(HomeWeatherDevice|HomeTwilightDevice)$/x)
    {
      if ($attr_name eq 'HomeWeatherDevice')
      {
        CommandDeleteReading(undef,"$name pressure|wind");
        CommandDeleteReading(undef,"$name temperature") if (!AttrVal($name,'HomeSensorTemperatureOutside',undef));
        CommandDeleteReading(undef,"$name humidity") if (!AttrVal($name,'HomeSensorHumidityOutside',undef));
      }
      else
      {
        CommandDeleteReading(undef,"$name twilight|twilightEvent|light");
      }
      updateInternals($hash);
    }
    elsif ($attr_name =~ /^(HomeSensorTemperatureOutside|HomeSensorHumidityOutside)$/x)
    {
      CommandDeleteReading(undef,"$name .*temperature.*") if (!AttrVal($name,'HomeWeatherDevice',undef) && $attr_name eq 'HomeSensorTemperatureOutside');
      CommandDeleteReading(undef,"$name .*humidity.*") if (!AttrVal($name,'HomeWeatherDevice',undef) && $attr_name eq 'HomeSensorHumidityOutside');
      updateInternals($hash);
    }
    elsif ($attr_name =~ /^(HomeAdvancedAttributes|HomeDaytimes|HomeSeasons|HomeSpecialLocations|HomeSpecialModes)$/x && $init_done)
    {
      AttrList($hash);
    }
    elsif ($attr_name =~ /^(HomeUWZ|HomeSensorsLuminance|HomeSensorsLuminanceReading|HomeSensorsPowerEnergyReadings)$/x)
    {
      CommandDeleteReading(undef,"$name uwz.*") if ($attr_name eq 'HomeUWZ');
      CommandDeleteReading(undef,"$name .*luminance.*") if ($attr_name eq 'HomeSensorsLuminance');
      updateInternals($hash);
    }
    elsif ($attr_name eq 'HomeSensorsBatteryLowPercentage')
    {
      updateInternals($hash);
    }
  }
  return;
}

sub replacePlaceholders
{
  my ($hash,$cmd,$resident) = @_;
  my $name = $hash->{NAME};
  my $sensor = AttrVal($name,'HomeWeatherDevice','nOtDeFiNeDwEaThErDeViCe');
  $resident = $resident ? $resident : ReadingsVal($name,'lastActivityByResident','');
  my $alias = AttrVal($resident,'alias','');
  my $audio = AttrVal($resident,'msgContactAudio','');
  $audio = AttrVal('globalMsg','msgContactAudio','no msg audio device available') if (!$audio);
  my $lastabsencedur = ReadingsVal($resident,'lastDurAbsence_cr',0);
  my $lastpresencedur = ReadingsVal($resident,'lastDurPresence_cr',0);
  my $lastsleepdur = ReadingsVal($resident,'lastDurSleep_cr',0);
  my $durabsence = ReadingsVal($resident,'durTimerAbsence_cr',0);
  my $durpresence = ReadingsVal($resident,'durTimerPresence_cr',0);
  my $dursleep = ReadingsVal($resident,'durTimerSleep_cr',0);
  # my $condition = ReadingsVal($sensor,'condition',ID($sensor)?'no data available':'no weather device available');
  # my $conditionart = ReadingsVal($name,'.be','');
  my $contactsOpen = ReadingsVal($name,'contactsOutsideOpen','');
  my $contactsOpenCt = ReadingsVal($name,'contactsOutsideOpen_ct',0);
  my $contactsOpenHr = ReadingsVal($name,'contactsOutsideOpen_hr',0);
  my $dnd = ReadingsVal($name,'dnd','off') eq 'on' ? 1 : 0;
  my $aeah = ReadingsVal($name,'anyoneElseAtHome','off') eq 'on' ? 1 : 0;
  my $panic = ReadingsVal($name,'panic','off') eq 'on' ? 1 : 0;
  my $tampered = ReadingsVal($name,'alarmTamper_hr','');
  my $tamperedc = ReadingsVal($name,'alarmTamper_ct','');
  my $tamperedhr = ReadingsVal($name,'alarmTamper_hr','');
  my $ice = ReadingsVal($name,'icewarning',0);
  my $ip = ReadingsVal($name,'publicIP','');
  my $light = ReadingsVal($name,'light',0);
  my $twilight = ReadingsVal($name,'twilight',0);
  my $twilightevent = ReadingsVal($name,'twilightEvent','');
  my $location = ReadingsVal($name,'location','');
  my $rlocation = ReadingsVal($resident,'location','');
  my $alarm = ReadingsVal($name,'alarmTriggered',0);
  my $alarmc = ReadingsVal($name,'alarmTriggered_ct',0);
  my $alarmhr = ReadingsVal($name,'alarmTriggered_hr',0);
  my $daytime = DayTime($hash);
  my $mode = ReadingsVal($name,'mode','');
  my $amode = ReadingsVal($name,'modeAlarm','');
  my $pamode = ReadingsVal($name,'prevModeAlarm','');
  my $season = ReadingsVal($name,'season','');
  my $pmode = ReadingsVal($name,'prevMode','');
  my $rpmode = ReadingsVal($resident,'lastState','');
  my $pres = ReadingsVal($name,'presence','') eq 'present' ? 1 : 0;
  my $rpres = ReadingsVal($resident,'presence','') eq 'present' ? 1 : 0;
  my $pdevice = ReadingsVal($name,'lastActivityByPresenceDevice','');
  my $apdevice = ReadingsVal($name,'lastAbsentByPresenceDevice','');
  my $ppdevice = ReadingsVal($name,'lastPresentByPresenceDevice','');
  my $paddress = InternalVal($pdevice,'ADDRESS','');
  # my $pressure = ReadingsVal($name,'pressure','');
  # my $weatherlong = WeatherTXT($hash,AttrVal($name,'HomeTextWeatherLong',''));
  # my $weathershort = WeatherTXT($hash,AttrVal($name,'HomeTextWeatherShort',''));
  my $forecast = ForecastTXT($hash);
  my $forecasttoday = ForecastTXT($hash,1);
  my $luminance = ReadingsVal($name,'luminance',0);
  my $luminancetrend = ReadingsVal($name,'luminanceTrend',0);
  # my $humi = ReadingsVal($name,'humidity',0);
  # my $humitrend = ReadingsVal($name,'humidityTrend',0);
  # my $temp = ReadingsVal($name,'temperature',0);
  # my $temptrend = ReadingsVal($name,'temperatureTrend','constant');
  # my $wind = ReadingsVal($name,'wind',0);
  # my $windchill = ReadingsVal($sensor,'apparentTemperature',ID($sensor)?'no data available':'no weather device available');
  my $motion = ReadingsVal($name,'lastMotion','');
  my $pmotion = ReadingsVal($name,'prevMotion','');
  my $contact = ReadingsVal($name,'lastContact','');
  my $pcontact = ReadingsVal($name,'prevContact','');
  my $uwzc = ReadingsVal($name,'uwz_warnCount',0);
  my $uwzs = uwzTXT($hash,$uwzc,undef);
  my $uwzl = uwzTXT($hash,$uwzc,1);
  my $lowBat = name2alias(ReadingsVal($name,'lastBatteryLow',''));
  my $normBat = name2alias(ReadingsVal($name,'lastBatteryNormal',''));
  my $lowBatAll = ReadingsVal($name,'batteryLow_hr','');
  my $lowBatCount = ReadingsVal($name,'batteryLow_ct',0);
  my $disabled = ReadingsVal($name,'devicesDisabled','');
  my $openwarn = ReadingsVal($name,'contactOpenWarning','');
  my $openwarnct = ReadingsNum($name,'contactOpenWarning_ct',0);
  my $openwarnhr = ReadingsVal($name,'contactOpenWarning_hr','');
  my $sensorsbattery = $hash->{SENSORSBATTERY};
  my $sensorscontact = $hash->{SENSORSCONTACT};
  my $sensorsenergy = $hash->{SENSORSENERGY};
  my $sensorsmotion = $hash->{SENSORSMOTION};
  my $sensorssmoke = $hash->{SENSORSSMOKE};
  my $ure = $hash->{RESIDENTS};
  $ure =~ s/,/\|/xg;
  my $arrivers = makeHR($hash,1,devspec2array("$ure:FILTER=location=arrival"));
  my $water = ReadingsVal($name,'alarmWater',0);
  my $waterc = ReadingsVal($name,'alarmWater_ct',0);
  my $waterhr = ReadingsVal($name,'alarmWater_hr',0);
  my $unified = AttrNum($name,'HomeSensorsContactOpenWarningUnified',0);
  $cmd = WeatherTXT($hash,$cmd);
  $cmd =~ s/%ADDRESS%/$paddress/xg;
  $cmd =~ s/%ALARM%/$alarm/xg;
  $cmd =~ s/%ALARMCT%/$alarmc/xg;
  $cmd =~ s/%ALARMHR%/$alarmhr/xg;
  $cmd =~ s/%ALIAS%/$alias/xg;
  $cmd =~ s/%AMODE%/$amode/xg;
  $cmd =~ s/%AEAH%/$aeah/xg;
  $cmd =~ s/%ARRIVERS%/$arrivers/xg;
  $cmd =~ s/%AUDIO%/$audio/xg;
  $cmd =~ s/%BATTERYNORMAL%/$normBat/xg;
  $cmd =~ s/%BATTERYLOW%/$lowBat/xg;
  $cmd =~ s/%BATTERYLOWALL%/$lowBatAll/xg;
  $cmd =~ s/%BATTERYLOWCT%/$lowBatCount/xg;
  # $cmd =~ s/%CONDITION%/$condition/xg;
  $cmd =~ s/%CONTACT%/$contact/xg;
  $cmd =~ s/%DAYTIME%/$daytime/xg;
  $cmd =~ s/%DEVICE%/$pdevice/xg;
  $cmd =~ s/%DEVICEA%/$apdevice/xg;
  $cmd =~ s/%DEVICEP%/$ppdevice/xg;
  $cmd =~ s/%DISABLED%/$disabled/xg;
  $cmd =~ s/%DND%/$dnd/xg;
  my $hed = AttrCheck($hash,'HomeEventsDevices',undef);
  if ($hed)
  {
    my @cals;
    for my $c (devspec2array($hed))
    {
      push @cals,$c;
    }
    @cals = uniq @cals;
    for my $cal (@cals)
    {
      my $state = ReadingsVal($name,"event-$cal",'none') ne 'none' ? ReadingsVal($name,"event-$cal",'') : '';
      $cmd =~ s/%$cal%/$state/xg;
      my $events = CalendarEvents($name,$cal);
      if (ID($cal,'holiday'))
      {
        for my $evt (@{$events})
        {
          my $val = $state eq $evt ? 1 : '';
          $cmd =~ s/%$cal-$evt%/$val/xg;
        }
      }
      else
      {
        for my $evt (@{$events})
        {
          for my $e (split /,/x,$state)
          {
            my $val = $e eq $evt ? 1 : '';
            $cmd =~ s/%$cal-$evt%/$val/xg;
          }
        }
      }
    }
  }
  $cmd =~ s/%DURABSENCE%/$durabsence/xg;
  $cmd =~ s/%DURABSENCELAST%/$lastabsencedur/xg;
  $cmd =~ s/%DURPRESENCE%/$durpresence/xg;
  $cmd =~ s/%DURPRESENCELAST%/$lastpresencedur/xg;
  $cmd =~ s/%DURSLEEP%/$dursleep/xg;
  $cmd =~ s/%DURSLEEPLAST%/$lastsleepdur/xg;
  $cmd =~ s/%FORECAST%/$forecast/xg;
  $cmd =~ s/%FORECASTTODAY%/$forecasttoday/xg;
  # $cmd =~ s/%HUMIDITY%/$humi/xg;
  # $cmd =~ s/%HUMIDITYTREND%/$humitrend/xg;
  $cmd =~ s/%ICE%/$ice/xg;
  $cmd =~ s/%IP%/$ip/xg;
  $cmd =~ s/%LIGHT%/$light/xg;
  $cmd =~ s/%LOCATION%/$location/xg;
  $cmd =~ s/%LOCATIONR%/$rlocation/xg;
  $cmd =~ s/%LUMINANCE%/$luminance/xg;
  $cmd =~ s/%LUMINANCETREND%/$luminancetrend/xg;
  $cmd =~ s/%MODE%/$mode/xg;
  $cmd =~ s/%MODEALARM%/$amode/xg;
  $cmd =~ s/%MOTION%/$motion/xg;
  $cmd =~ s/%NAME%/$name/xg;
  $cmd =~ s/%OPEN%/$contactsOpen/xg;
  $cmd =~ s/%OPENCT%/$contactsOpenCt/xg;
  $cmd =~ s/%OPENHR%/$contactsOpenHr/xg;
  $cmd =~ s/%OPENWARN%/$openwarn/xg;
  $cmd =~ s/%OPENWARNCT%/$openwarnct/xg;
  $cmd =~ s/%OPENWARNHR%/$openwarnhr/xg;
  $cmd =~ s/%RESIDENT%/$resident/xg;
  $cmd =~ s/%PANIC%/$panic/xg;
  $cmd =~ s/%PRESENT%/$pres/xg;
  $cmd =~ s/%PRESENTR%/$rpres/xg;
  # $cmd =~ s/%PRESSURE%/$pressure/xg;
  $cmd =~ s/%PREVAMODE%/$pamode/xg;
  $cmd =~ s/%PREVCONTACT%/$pcontact/xg;
  $cmd =~ s/%PREVMODE%/$pmode/xg;
  $cmd =~ s/%PREVMODER%/$rpmode/xg;
  $cmd =~ s/%PREVMOTION%/$pmotion/xg;
  $cmd =~ s/%SEASON%/$season/xg;
  $cmd =~ s/%SELF%/$name/xg;
  $cmd =~ s/%SENSORSBATTERY%/$sensorsbattery/xg;
  $cmd =~ s/%SENSORSCONTACT%/$sensorscontact/xg;
  $cmd =~ s/%SENSORSENERGY%/$sensorsenergy/xg;
  $cmd =~ s/%SENSORSMOTION%/$sensorsmotion/xg;
  $cmd =~ s/%SENSORSSMOKE%/$sensorssmoke/xg;
  $cmd =~ s/%TAMPERED%/$tampered/xg;
  $cmd =~ s/%TAMPEREDCT%/$tamperedc/xg;
  $cmd =~ s/%TAMPEREDHR%/$tamperedhr/xg;
  # $cmd =~ s/%TEMPERATURE%/$temp/xg;
  # $cmd =~ s/%TEMPERATURETREND%/$temptrend/xg;
  # $cmd =~ s/%TOBE%/$conditionart/xg;
  $cmd =~ s/%TWILIGHT%/$twilight/xg;
  $cmd =~ s/%TWILIGHTEVENT%/$twilightevent/xg;
  $cmd =~ s/%UNIFIED%/$unified/xg;
  $cmd =~ s/%UWZ%/$uwzc/xg;
  $cmd =~ s/%UWZLONG%/$uwzl/xg;
  $cmd =~ s/%UWZSHORT%/$uwzs/xg;
  $cmd =~ s/%WATER%/$water/xg;
  $cmd =~ s/%WATERCT%/$waterc/xg;
  $cmd =~ s/%WATERHR%/$waterhr/xg;
  # $cmd =~ s/%WEATHER%/$weathershort/xg;
  # $cmd =~ s/%WEATHERLONG%/$weatherlong/xg;
  # $cmd =~ s/%WIND%/$wind/xg;
  # $cmd =~ s/%WINDCHILL%/$windchill/xg;
  return $cmd;
}

sub serializeCMD
{
  my ($hash,@cmds) = @_;
  my $name = $hash->{NAME};
  my @newcmds;
  for my $cmd (@cmds)
  {
    $cmd =~ s/\r\n/\n/xgm;
    my @newcmd;
    for (split /\n+/x,$cmd)
    {
      next if ($_ =~ /^\s*(#|$)/);
      $_ =~ s/\s{2,}/ /g;
      push @newcmd,$_;
    }
    $cmd = join(' ',@newcmd);
    Log3 $name,5,"$name: cmdnew: $cmd";
    push @newcmds,SemicolonEscape($cmd) if ($cmd !~ /^[\t\s]*$/);
  }
  my $cmd = join(';',@newcmds);
  $cmd =~ s/\}\s{0,1};\s{0,1}\{/\};;\{/g;
  return $cmd;
}

sub ReadingTrend
{
  my ($hash,$read,$val) = @_;
  my $name = $hash->{NAME};
  $val = ReadingsNum($name,$read,5) if (!$val);
  my $time = AttrNum($name,'HomeTrendCalcAge',900);
  my $pval = ReadingsNum($name,".$read",undef);
  if (defined $pval && ReadingsAge($name,".$read",0) >= $time)
  {
    my ($rising,$constant,$falling) = split /\|/x,AttrVal($name,'HomeTextRisingConstantFalling','rising|constant|falling');
    my $trend = $constant;
    $trend = $rising if ($val > $pval);
    $trend = $falling if ($val < $pval);
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,".$read",$val);
    readingsBulkUpdate($hash,$read.'Trend',$trend);
    readingsEndUpdate($hash,1);
  }
  elsif (!defined $pval)
  {
    readingsSingleUpdate($hash,".$read",$val,0);
  }
  return;
}

sub WeatherTXT
{
  my ($hash,$text) = @_;
  my $name = $hash->{NAME};
  my $weather = AttrVal($name,'HomeWeatherDevice','');
  my $condition = ReadingsVal($weather,'condition','');
  my $conditionart = ReadingsVal($name,'.be','');
  my $pressure = ReadingsVal($name,'pressure','');
  my $pressuret = ReadingsVal($name,'pressureTrend','');
  my $humi = ReadingsVal($name,'humidity',0);
  my $humitrend = ReadingsVal($name,'humidityTrend',0);
  my $temp = ReadingsVal($name,'temperature',0);
  my $tempt = ReadingsVal($name,'temperatureTrend',0);
  my $windchill = ReadingsNum($weather,'apparentTemperature',0);
  my $wind = ReadingsVal($name,'wind',0);
  my $ws = ReadingsVal($name,'weatherTextShort','<NO TEXT WEATHER SHORT TEXT AVAILABLE>');
  my $wl = ReadingsVal($name,'weatherTextLong','<NO TEXT WEATHER LONG TEXT VAILABLE>');
  $text =~ s/%CONDITION%/$condition/xg;
  $text =~ s/%HUMIDITY%/$humi/xg;
  $text =~ s/%HUMIDITYTREND%/$humitrend/xg;
  $text =~ s/%PRESSURE%/$pressure/xg;
  $text =~ s/%PRESSURETREND%/$pressuret/xg;
  $text =~ s/%TEMPERATURE%/$temp/xg;
  $text =~ s/%TEMPERATURETREND%/$tempt/xg;
  $text =~ s/%TOBE%/$conditionart/xg;
  $text =~ s/%WEATHER%/$ws/xg;
  $text =~ s/%WEATHERLONG%/$wl/xg;
  $text =~ s/%WINDCHILL%/$windchill/xg;
  $text =~ s/%WIND%/$wind/xg;
  return $text;
}

sub ForecastTXT
{
  my ($hash,$day) = @_;
  $day = 2 if (!$day);
  my $name = $hash->{NAME};
  my $weather = AttrVal($name,'HomeWeatherDevice','');
  my $cond = ReadingsVal($weather,'fc'.$day.'_condition','n.a.');
  my $low  = ReadingsVal($weather,'fc'.$day.'_low_c','n.a.');
  my $high = ReadingsVal($weather,'fc'.$day.'_high_c','n.a.');
  my $temp = ReadingsVal($name,'temperature','');
  my $hum = ReadingsVal($name,'humidity','');
  my $chill = ReadingsNum($weather,'apparentTemperature',0);
  my $wind = ReadingsVal($name,'wind','');
  my $text;
  if (defined $cond && defined $low && defined $high)
  {
    my ($today,$tomorrow,$atomorrow) = split /\|/x,AttrVal($name,'HomeTextTodayTomorrowAfterTomorrow','today|tomorrow|day after tomorrow');
    my $d = $today;
    $d = $tomorrow  if ($day == 2);
    $d = $atomorrow if ($day == 3);
    $d = $day-1     if ($day >  3);
    $text = AttrVal($name,'HomeTextWeatherForecastToday','');
    $text = AttrVal($name,'HomeTextWeatherForecastTomorrow','')    if ($day =~ /^[23]$/x);
    $text = AttrVal($name,'HomeTextWeatherForecastInSpecDays','')  if ($day > 3);
    $text =~ s/%CONDITION%/$cond/xg;
    $text =~ s/%DAY%/$d/xg;
    $text =~ s/%HIGH%/$high/xg;
    $text =~ s/%LOW%/$low/xg;
    $text = WeatherTXT($hash,$text);
  }
  else
  {
    $text = AttrVal($name,'HomeTextWeatherNoForecast','No forecast available');
  }
  return $text;
}

sub uwzTXT
{
  my ($hash,$count,$sl) = @_;
  my $name = $hash->{NAME};
  $count = defined $count ? $count : ReadingsVal($name,'uwz_warnCount',0);
  my $text = '';
  for (my $i = 0; $i < $count; $i++)
  {
    $text .= ' ' if ($i > 0);
    $text .= $i + 1 . '. ' if ($count > 1);
    $sl = $sl ? 'LongText':'ShortText';
    $text .= ReadingsVal(AttrVal($name,'HomeUWZ',''),'Warn_'.$i.'_'.$sl,'');
  }
  return $text;
}

sub ID
{
  my ($devname,$devtype,$devread,$readval) = @_;
  return 0
    if (!defined($devname) || !defined($defs{$devname}));
  return 0
    if (defined($devtype) && $defs{$devname}{TYPE} !~ /^$devtype$/x);
  return 0
    if (defined($devread) && !defined(ReadingsVal($devname,$devread,undef)));
  return 0
    if (defined($readval) && ReadingsVal($devname,$devread,'') !~ /^$readval$/x);
  return $devname;
}

sub CheckIfIsValidDevspec
{
  my ($name,$spec,$read) = @_;
  my $hash = $defs{$name};
  my @names;
  for (devspec2array($spec))
  {
    next unless (ID($_,undef,$read));
    push @names,$_;
  }
  return \@names if (@names);
  return;
}

sub execUserCMDs
{
  my ($string) = @_;
  my ($name,$cmds,$resident) = split /\|/x,$string;
  my $hash = $defs{$name};
  $cmds = decode_base64($cmds);
  execCMDs($hash,$cmds,$resident);
  return;
}

sub execCMDs
{
  my ($hash,$cmds,$resident) = @_;
  my $name = $hash->{NAME};
  my $cmd = replacePlaceholders($hash,$cmds,$resident);
  my $err = AnalyzeCommandChain(undef,$cmd);
  if ($err && $err !~ /^Deleted.reading|Wrote.configuration|good|Scheduled.for.sending.after.WAKEUP/)
  {
    Log3 $name,3,"$name: error: $err";
    Log3 $name,3,"$name: error in command: $cmd";
    readingsSingleUpdate($hash,'lastCMDerror',"error: >$err< in CMD: $cmd",1);
  }
  Log3 $name,4,"$name: executed CMDs: $cmd";
  return;
}

sub AttrCheck
{
  my ($hash,$attribute,$default) = @_;
  $default = '' if (!defined $default);
  my $name = $hash->{NAME};
  my $value;
  if ($hash->{helper}{lastChangedAttr} && $hash->{helper}{lastChangedAttr} eq $attribute)
  {
    $value = defined $hash->{helper}{lastChangedAttrValue} && $hash->{helper}{lastChangedAttrValue} ne '---' ? $hash->{helper}{lastChangedAttrValue} : $default;
  }
  else
  {
    $value = AttrVal($name,$attribute,$default);
  }
  return $value;
}

sub DayTime
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $daytimes = AttrCheck($hash,'HomeDaytimes',$HOMEMODE_Daytimes);
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
  my $loctime = $hour * 60 + $min;
  my @texts;
  my @times;
  for (split ' ',$daytimes)
  {
    my ($dt,$text) = split /\|/x;
    my ($h,$m) = split /:/x,$dt;
    my $minutes = $h * 60 + $m;
    push @times,$minutes;
    push @texts,$text;
  }
  my $daytime = $texts[int(@texts) - 1];
  for (my $x = 0; $x < int(@times); $x++)
  {
    my $y = $x==int(@times)-1?0:$x+1;
    $daytime = $texts[$x] if ($y > $x && $loctime >= $times[$x] && $loctime < $times[$y]);
  }
  return $daytime;
}

sub SetDaytime
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dt = DayTime($hash);
  my $dtr = makeReadingName($dt);
  if (ReadingsVal($name,'daytime','') ne $dt)
  {
    Log3 $name,4,"$name SetDaytime daytime: $dt";
    my @commands;
    push @commands,AttrVal($name,'HomeCMDdaytime','') if (AttrVal($name,'HomeCMDdaytime',undef));
    push @commands,AttrVal($name,"HomeCMDdaytime-$dtr",'') if (AttrVal($name,"HomeCMDdaytime-$dtr",undef));
    readingsSingleUpdate($hash,'daytime',$dt,1);
    execCMDs($hash,serializeCMD($hash,@commands)) if (@commands);
  }
  return;
}

sub SetSeason
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $seasons = AttrCheck($hash,'HomeSeasons',$HOMEMODE_Seasons);
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
  my $locdays = ($month + 1) * 31 + $mday;
  my @texts;
  my @dates;
  for (split ' ',$seasons)
  {
    my ($date,$text) = split /\|/x;
    my ($m,$d) = split /\./x,$date;
    my $days = $m * 31 + $d;
    push @dates,$days;
    push @texts,$text;
  }
  my $season = $texts[int(@texts)-1];
  for (my $x = 0; $x < int(@dates); $x++)
  {
    my $y = $x==int(@dates)-1?0:$x+1;
    $season = $texts[$x] if ($y > $x && $locdays >= $dates[$x] && $locdays < $dates[$y]);
  }
  if (ReadingsVal($name,'season','') ne $season)
  {
    my @commands;
    push @commands,AttrVal($name,'HomeCMDseason','') if (AttrVal($name,'HomeCMDseason',undef));
    push @commands,AttrVal($name,'HomeCMDseason-'.makeReadingName($season),'') if (AttrVal($name,'HomeCMDseason-'.makeReadingName($season),undef));
    readingsSingleUpdate($hash,'season',$season,1);
    execCMDs($hash,serializeCMD($hash,@commands)) if (@commands);
  }
  return;
}

sub hourMaker
{
  my ($minutes) = @_;
  my $text = $langDE?
    'keine gültigen Minuten übergeben':
    'no valid minutes given';
  return $text if ($minutes !~ /^(\d{1,4})(\.\d{0,2})?$/x || $1 >= 6000 || $minutes < 0.01);
  my $hours = int($minutes / 60);
  $hours = length $hours > 1 ? $hours : "0$hours";
  my $min = $minutes % 60;
  $min = length $min > 1 ? $min : "0$min";
  my $sec = int(($minutes - int($minutes)) * 60);
  $sec = length $sec > 1 ? $sec : "0$sec";
  return "$hours:$min:$sec";
}

sub addSensorsUserAttr
{
  my ($hash,$devs,$olddevs) = @_;
  return if (!$devs || !$init_done);
  my $name = $hash->{NAME};
  my @devspec = devspec2array($devs);
  my @olddevspec;
  @olddevspec = devspec2array($olddevs) if ($olddevs);
  my $migrate = $hash->{helper}{migrate};
  $olddevs = $devs if (!$olddevs && $migrate);
  cleanUserattr($hash,$olddevs,$devs) if ($olddevs);
  for my $sensor (@devspec)
  {
    next if (InternalVal($sensor,'TYPE','') =~ /^global|calendar|holiday|weather|uwz$/xi);
    my $inolddevspec = @olddevspec && (grep {$_ eq $sensor} @olddevspec) ? 1 : 0;
    my $alias = AttrVal($sensor,'alias','');
    my @list;
    if ((grep {$_ eq $sensor} split /,/x,InternalVal($name,'SENSORSCONTACT','')) || (grep {$_ eq $sensor} split /,/x,InternalVal($name,'SENSORSMOTION','')))
    {
      push @list,'HomeModeAlarmActive';
      push @list,'HomeAlarmDelay';
    }
    if (grep {$_ eq $sensor} split /,/x,InternalVal($name,'SENSORSCONTACT',''))
    {
      push @list,'HomeContactType:doorinside,dooroutside,doormain,window';
      # push @list,'HomeCMDcontactOpen:textField-long';
      # push @list,'HomeCMDcontactClose:textField-long';
      push @list,'HomeOpenDontTriggerModes';
      push @list,'HomeOpenDontTriggerModesResidents';
      push @list,'HomeOpenMaxTrigger';
      if (AttrVal($name,'HomeSensorsContactOpenWarningUnified',0))
      {
        push @list,'HomeOpenTimes';
        push @list,'HomeOpenTimeDividers';
      }
      push @list,'HomeReadingContact';
      push @list,'HomeValueContact';
      push @list,'HomeReadingTamper' if ($migrate);
      push @list,'HomeValueTamper' if ($migrate);
      if (!$inolddevspec)
      {
        my $dr = '[Dd]oor|[Tt](ü|ue)r';
        my $wr = '[Ww]indow|[Ff]enster';
        CommandAttr(undef,"$sensor HomeContactType doorinside") if (($alias =~ /$dr/x || $sensor =~ /$dr/x) && !AttrVal($sensor,'HomeContactType',''));
        CommandAttr(undef,"$sensor HomeContactType window") if (($alias =~ /$wr/x || $sensor =~ /$wr/x) && !AttrVal($sensor,'HomeContactType',''));
        CommandAttr(undef,"$sensor HomeModeAlarmActive armaway") if (!AttrVal($sensor,'HomeModeAlarmActive',''));
      }
    }
    if (grep {$_ eq $sensor} split /,/x,InternalVal($name,'SENSORSMOTION',''))
    {
      push @list,'HomeSensorLocation:inside,outside';
      push @list,'HomeReadingMotion';
      push @list,'HomeValueMotion';
      if (!$inolddevspec)
      {
        my $loc = 'inside';
        $loc = 'outside' if ($alias =~ /([Aa]u(ss|ß)en)|([Oo]ut)/x || $sensor =~ /([Aa]u(ss|ß)en)|([Oo]ut)/x);
        CommandAttr(undef,"$sensor HomeSensorLocation $loc") if (!AttrVal($sensor,'HomeSensorLocation',''));
        CommandAttr(undef,"$sensor HomeModeAlarmActive armaway") if (!AttrVal($sensor,'HomeModeAlarmActive','') && $loc eq 'inside');
      }
    }
    if (grep {$_ eq $sensor} split /,/x,InternalVal($name,'SENSORSBATTERY',''))
    {
      push @list,'HomeReadingBattery';
      push @list,'HomeBatteryLowPercentage';
    }
    if (grep {$_ eq $sensor} split /,/x,InternalVal($name,'SENSORSSMOKE',''))
    {
      push @list,'HomeReadingSmoke';
      push @list,'HomeValueSmoke';
    }
    if (grep {$_ eq $sensor} split /,/x,InternalVal($name,'SENSORSTAMPER',''))
    {
      push @list,'HomeReadingTamper';
      push @list,'HomeValueTamper';
    }
    if (grep {$_ eq $sensor} split /,/x,InternalVal($name,'SENSORSWATER',''))
    {
      push @list,'HomeReadingWater';
      push @list,'HomeValueWater';
    }
    if (grep {$_ eq $sensor} split /,/x,InternalVal($name,'SENSORSENERGY',''))
    {
      push @list,'HomeReadingEnergy';
      push @list,'HomeDividerEnergy';
      push @list,'HomeAllowNegativeEnergy:0,1';
    }
    if (grep {$_ eq $sensor} split /,/x,InternalVal($name,'SENSORSPOWER',''))
    {
      push @list,'HomeReadingPower';
      push @list,'HomeDividerPower';
      push @list,'HomeAllowNegativePower:0,1';
    }
    if (grep {$_ eq $sensor} split /,/x,InternalVal($name,'SENSORSLIGHT',''))
    {
      push @list,'HomeReadingLuminance';
      push @list,'HomeDividerLuminance';
    }
    @list = uniq sort @list;
    set_userattr($sensor,\@list);
  }
  return;
}

sub set_userattr
{
  my ($name,$list) = @_;
  my $hash = $defs{$name};
  Log3 $name,4,"$name set_userattr";
  my $val = AttrVal($name,'userattr','');
  my $l = join ' ',@{$list};
  $l .= $val?" $val":'';
  CommandAttr(undef,"$name userattr $l") if ($l && $l ne $val);
  return;
}

sub Luminance
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my @sensorsa;
  my $lum = 0;
  for (split /,/x,$hash->{SENSORSLIGHT})
  {
    next if (IsDis($name,$_));
    push @sensorsa,$_;
    my $read = AttrVal($_,'HomeReadingLuminance',AttrVal($name,'HomeSensorsLuminanceReading','luminance'));
    my $val = ReadingsNum($_,$read,0);
    next unless ($val > 0);
    my $div = AttrVal($_,'HomeDividerLuminance',1);
    $lum += $val/$div;
  }
  return if (!int(@sensorsa));
  my $lumval = int($lum/int(@sensorsa));
  readingsSingleUpdate($hash,'luminance',$lumval,1);
  ReadingTrend($hash,'luminance',$lumval);
  return;
}

sub TriggerState
{
  my ($hash,$getter,$type,$trigger) = @_;
  my $exit = (!$getter && !$type && $trigger)?1:undef;
  $getter  = $getter?$getter:'contactsOpen';
  $type = $type?$type:'all';
  my $name = $hash->{NAME};
  my $events = $trigger?deviceEvents($defs{$trigger},1):undef;
  my $contacts = $hash->{SENSORSCONTACT};
  my $motions = $hash->{SENSORSMOTION};
  my $alarm = ReadingsVal($name,'alarmTriggered','');
  my @contactsOpen;
  my @doorsOOpen;
  my @doorsMOpen;
  my @insideOpen;
  my @outsideOpen;
  my @windowsOpen;
  my @motionsOpen;
  my @motionsInsideOpen;
  my @motionsOutsideOpen;
  my @alarmSensors;
  my @lightSensors;
  my $amode = ReadingsVal($name,'modeAlarm','disarm');
  if ($contacts)
  {
    for my $sensor (split /,/,$contacts)
    {
      next if (IsDis($name,$sensor));
      my $read = AttrVal($sensor,'HomeReadingContact',AttrVal($name,'HomeSensorsContactReading','state'));
      my $val = AttrVal($sensor,'HomeValueContact',AttrVal($name,'HomeSensorsContactValues','open|tilted|on|1|true'));
      my $state = ReadingsVal($sensor,$read,'');
      my $amodea = AttrVal($sensor,'HomeModeAlarmActive','-');
      my $kind = AttrVal($sensor,'HomeContactType','window');
      next if (!$state);
      if ($state =~ /^$val$/)
      {
        push @contactsOpen,$sensor;
        push @insideOpen,$sensor if ($kind eq 'doorinside');
        push @doorsOOpen,$sensor if ($kind && $kind eq 'dooroutside');
        push @doorsMOpen,$sensor if ($kind && $kind eq 'doormain');
        push @outsideOpen,$sensor if ($kind =~ /^dooroutside|doormain|window$/x);
        push @windowsOpen,$sensor if ($kind eq 'window');
        if ($amode =~ /^$amodea$/)
        {
          push @alarmSensors,$sensor;
        }
        if (defined $exit && $trigger eq $sensor && grep {/^$read:/x} @{$events})
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,'prevContact',ReadingsVal($name,'lastContact',''));
          readingsBulkUpdate($hash,'lastContact',$sensor);
          readingsEndUpdate($hash,1);
          ContactCommands($hash,$sensor,'open',$kind);
          ContactOpenWarning($name,$sensor);
        }
      }
      else
      {
        if (defined $exit && $trigger eq $sensor && grep {/^$read:/x} @{$events})
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,'prevContactClosed',ReadingsVal($name,'lastContactClosed',''));
          readingsBulkUpdate($hash,'lastContactClosed',$sensor);
          readingsEndUpdate($hash,1);
          ContactCommands($hash,$sensor,'closed',$kind);
          my $timer = 'atTmp_HomeOpenTimer_'.$sensor.'_'.$name;
          CommandDelete(undef,$timer) if (ID($timer,'at'));
          CommandDeleteReading(undef,"$trigger .".$name.'-HomeOpenTrigger');
          ContactOpenWarning($name,$sensor);
        }
      }
    }
  }
  if ($motions)
  {
    for my $sensor (split /,/,$motions)
    {
      next if (IsDis($name,$sensor));
      my $read = AttrVal($sensor,'HomeReadingMotion',AttrVal($name,'HomeSensorsMotionReading','state'));
      my $val = AttrVal($sensor,'HomeValueMotion',AttrVal($name,'HomeSensorsMotionValues','open|on|motion|1|true'));
      my $amodea = AttrVal($sensor,'HomeModeAlarmActive','-');
      my $state = ReadingsVal($sensor,$read,'');
      my $kind = AttrVal($sensor,'HomeSensorLocation','inside');
      next if (!$state);
      if ($state =~ /^($val)$/x)
      {
        push @motionsOpen,$sensor;
        push @motionsInsideOpen,$sensor if ($kind eq 'inside');
        push @motionsOutsideOpen,$sensor if ($kind eq 'outside');
        if ($amode =~ /^($amodea)$/x)
        {
          push @alarmSensors,$sensor;
        }
        if (defined $exit && $trigger eq $sensor && grep {/^$read:/x} @{$events})
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,'prevMotion',ReadingsVal($name,'lastMotion',''));
          readingsBulkUpdate($hash,'lastMotion',$sensor);
          readingsEndUpdate($hash,1);
          MotionCommands($hash,$sensor,'open');
        }
      }
      else
      {
        if (defined $exit && $trigger eq $sensor && grep {/^$read:/x} @{$events})
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,'prevMotionClosed',ReadingsVal($name,'lastMotionClosed',''));
          readingsBulkUpdate($hash,'lastMotionClosed',$sensor);
          readingsEndUpdate($hash,1);
          MotionCommands($hash,$sensor,'closed');
        }
      }
    }
  }
  alarmTriggered($hash,@alarmSensors) if (join(',',@alarmSensors) ne $alarm);
  my $open    = @contactsOpen ? join(',',@contactsOpen) : '';
  my $opendo  = @doorsOOpen ? join(',',@doorsOOpen) : '';
  my $opendm  = @doorsMOpen ? join(',',@doorsMOpen) : '';
  my $openi   = @insideOpen ? join(',',@insideOpen) : '';
  my $openm   = @motionsOpen ? join(',',@motionsOpen) : '';
  my $openmi  = @motionsInsideOpen ? join(',',@motionsInsideOpen) : '';
  my $openmo  = @motionsOutsideOpen ? join(',',@motionsOutsideOpen) : '';
  my $openo   = @outsideOpen ? join(',',@outsideOpen) : '';
  my $openw   = @windowsOpen ? join(',',@windowsOpen) : '';
  readingsBeginUpdate($hash);
  if ($contacts)
  {
    readingsBulkUpdateIfChanged($hash,'contactsDoorsInsideOpen',$openi);
    readingsBulkUpdateIfChanged($hash,'contactsDoorsInsideOpen_ct',@insideOpen);
    readingsBulkUpdateIfChanged($hash,'contactsDoorsInsideOpen_hr',makeHR($hash,0,@insideOpen));
    readingsBulkUpdateIfChanged($hash,'contactsDoorsOutsideOpen',$opendo);
    readingsBulkUpdateIfChanged($hash,'contactsDoorsOutsideOpen_ct',@doorsOOpen);
    readingsBulkUpdateIfChanged($hash,'contactsDoorsOutsideOpen_hr',makeHR($hash,0,@doorsOOpen));
    readingsBulkUpdateIfChanged($hash,'contactsDoorsMainOpen',$opendm);
    readingsBulkUpdateIfChanged($hash,'contactsDoorsMainOpen_ct',@doorsMOpen);
    readingsBulkUpdateIfChanged($hash,'contactsDoorsMainOpen_hr',makeHR($hash,0,@doorsMOpen));
    readingsBulkUpdateIfChanged($hash,'contactsOpen',$open);
    readingsBulkUpdateIfChanged($hash,'contactsOpen_ct',@contactsOpen);
    readingsBulkUpdateIfChanged($hash,'contactsOpen_hr',makeHR($hash,0,@contactsOpen));
    readingsBulkUpdateIfChanged($hash,'contactsOutsideOpen',$openo);
    readingsBulkUpdateIfChanged($hash,'contactsOutsideOpen_ct',@outsideOpen);
    readingsBulkUpdateIfChanged($hash,'contactsOutsideOpen_hr',makeHR($hash,0,@outsideOpen));
    readingsBulkUpdateIfChanged($hash,'contactsWindowsOpen',$openw);
    readingsBulkUpdateIfChanged($hash,'contactsWindowsOpen_ct',@windowsOpen);
    readingsBulkUpdateIfChanged($hash,'contactsWindowsOpen_hr',makeHR($hash,0,@windowsOpen));
  }
  if ($motions)
  {
    readingsBulkUpdateIfChanged($hash,'motionsSensors',$openm);
    readingsBulkUpdateIfChanged($hash,'motionsSensors_ct',@motionsOpen);
    readingsBulkUpdateIfChanged($hash,'motionsSensors_hr',makeHR($hash,0,@motionsOpen));
    readingsBulkUpdateIfChanged($hash,'motionsInside',$openmi);
    readingsBulkUpdateIfChanged($hash,'motionsInside_ct',@motionsInsideOpen);
    readingsBulkUpdateIfChanged($hash,'motionsInside_hr',makeHR($hash,0,@motionsInsideOpen));
    readingsBulkUpdateIfChanged($hash,'motionsOutside',$openmo);
    readingsBulkUpdateIfChanged($hash,'motionsOutside_ct',@motionsOutsideOpen);
    readingsBulkUpdateIfChanged($hash,'motionsOutside_hr',makeHR($hash,0,@motionsOutsideOpen));
  }
  readingsEndUpdate($hash,1);
  if ($getter eq 'contactsOpen')
  {
    return "open contacts: $open" if ($open && $type eq 'all');
    return 'no open contacts' if (!$open && $type eq 'all');
    return "open doorsinside: $openi" if ($openi && $type eq 'doorsinside');
    return 'no open doorsinside' if (!$openi && $type eq 'doorsinside');
    return "open doorsoutside: $opendo" if ($opendo && $type eq 'doorsoutside');
    return 'no open doorsoutside' if (!$opendo && $type eq 'doorsoutside');
    return "open doorsmain: $opendm" if ($opendm && $type eq 'doorsmain');
    return 'no open doorsmain' if (!$opendm && $type eq 'doorsmain');
    return "open outside: $openo" if ($openo && $type eq 'outside');
    return 'no open outside' if (!$openo && $type eq 'outside');
    return "open windows: $openw" if ($openw && $type eq 'windows');
    return 'no open windows' if (!$openw && $type eq 'windows');
  }
  return;
}

sub name2alias
{
  my ($name,$witharticle) = @_;
  my $alias = AttrVal($name,'alias',$name);
  my $art;
  $art = 'die' if ($alias =~ /t(ü|ue)r/xi);
  $art = 'das' if ($alias =~ /fenster/xi);
  $art = 'der' if ($alias =~ /(sensor|dete[ck]tor|melder|kontakt)$/xi);
  $art = 'der' if ($alias =~ /^(sensor|dete[ck]tor|melder|kontakt)\s.+/i);
  my $ret = $witharticle && $art ? "$art $alias" : $alias;
  return $ret;
}

sub ContactOpenWarning
{
  my ($name,$contact,$retrigger) = @_;
  my $maxtrigger = AttrNum($contact,'HomeOpenMaxTrigger',0);
  return if (!$maxtrigger);
  my $hash = $defs{$name};
  $retrigger = defined $retrigger?$retrigger:0;
  my $unified = AttrNum($name,'HomeSensorsContactOpenWarningUnified',0);
  my $timer = 'atTmp_HomeOpenTimer_'.($unified?'unified':$contact).'_'.$name;
  return if ($unified && ID($timer,'at'));
  my $mode = ReadingsVal($name,'mode','');
  my @warn;
  my $donttrigger;
  my (@warn1,@warnexp);
  my ($mt,$rt);
  for my $sen (devspec2array($hash->{SENSORSCONTACT}))
  {
    my $omt = AttrNum($sen,'HomeOpenMaxTrigger',0);
    my $otr = ReadingsNum($sen,'.'.$name.'-HomeOpenTrigger',0);
    my $dif = $omt-$otr;
    next if ($dif > $omt+1);
    my $sta = ReadingsVal($sen,AttrVal($sen,'HomeReadingContact',AttrVal($name,'HomeSensorsContactReading','state')),'');
    my $reg = AttrVal($sen,'HomeValueContact',AttrVal($name,'HomeSensorsContactValues','open|tilted|on|1|true'));
    next if ($sta !~ /^$reg$/);
    my $dtmode = AttrVal($sen,'HomeOpenDontTriggerModes','');
    my $dtres = AttrVal($sen,'HomeOpenDontTriggerModesResidents','');
    if ($dtres && $dtmode)
    {
      for (devspec2array($dtres))
      {
        $donttrigger = 1 if (ReadingsVal($_,'state','') =~ /^$dtmode$/x);
      }
    }
    elsif ($dtmode)
    {
      $donttrigger = 1 if ($mode =~ /^$dtmode$/)
    }
    next if ($donttrigger);
    if ($dif>-1)
    {
      $mt += $omt;
      $rt += $otr;
      push @warn,$sen if (!$retrigger || ($retrigger && $dif<$omt));
    }
    push @warn1,$sen if ($dif>0 && $dif<$omt);
    push @warnexp,$sen if ($dif<1);
    $otr++;
    readingsSingleUpdate($defs{$sen},'.'.$name.'-HomeOpenTrigger',$otr,0) if ($otr<=$omt+1);
  }
  if (!$unified)
  {
    @warn = (grep {$_ eq $contact} @warn)?($contact):();
  }
  else
  {
    $maxtrigger = $mt;
    $retrigger = $rt;
  }
  my $openwarn = join ',',sort @warn1;
  my $openwarnexp = join ',',sort @warnexp;
  readingsBeginUpdate($hash);
  readingsBulkUpdateIfChanged($hash,'contactWarning',$openwarn);
  readingsBulkUpdateIfChanged($hash,'contactWarning_ct',int(@warn1));
  readingsBulkUpdateIfChanged($hash,'contactWarning_hr',makeHR($hash,0,@warn1));
  readingsBulkUpdateIfChanged($hash,'contactWarningExpired',$openwarnexp);
  readingsBulkUpdateIfChanged($hash,'contactWarningExpired_ct',int(@warnexp));
  readingsBulkUpdateIfChanged($hash,'contactWarningExpired_hr',makeHR($hash,0,@warnexp));
  readingsEndUpdate($hash,1);
  CommandDelete(undef,$timer) if (ID($timer,'at') && ($retrigger || $donttrigger));
  return if ($donttrigger || !int(@warn));
  my $season = ReadingsVal($name,'season','');
  my $seasons = AttrVal($name,'HomeSeasons',$HOMEMODE_Seasons);
  my $dividers = $unified?AttrVal($name,'HomeSensorsContactOpenTimeDividers',''):AttrVal($contact,'HomeOpenTimeDividers',AttrVal($name,'HomeSensorsContactOpenTimeDividers',''));
  my $mintime = AttrNum($name,'HomeSensorsContactOpenTimeMin',0);
  my $otimes = $unified?AttrVal($name,'HomeSensorsContactOpenTimes',10):AttrVal($contact,'HomeOpenTimes',AttrVal($name,'HomeSensorsContactOpenTimes',10));
  my @wt = split ' ',$otimes;
  my $waittime;
  Log3 $name,5,"$name: retrigger: $retrigger";
  $waittime = $wt[$retrigger] if ($wt[$retrigger]);
  $waittime = $wt[int(@wt) - 1] if (!defined $waittime);
  Log3 $name,5,"$name: waittime real: $waittime";
  if ($dividers && AttrVal($contact,'HomeContactType','window') !~ /^door(inside|main)$/x)
  {
    my @divs = split ' ',$dividers;
    my $divider = 1;
    my $count = 0;
    for (split ' ',$seasons)
    {
      my (undef,$text) = split /\|/x;
      if ($season eq $text)
      {
        my $div = $divs[$count];
        $divider = $div if ($div && $div =~ /^\d{1,2}(\.\d{1,3})?$/x);
        last;
      }
      $count++;
    }
    return if (!$divider);
    $waittime = $waittime / $divider;
    $waittime = sprintf('%.2f',$waittime) * 1;
  }
  $waittime = $mintime if ($waittime < $mintime);
  $retrigger++;
  Log3 $name,5,"$name: waittime divided: $waittime";
  $waittime = hourMaker($waittime);
  Debug "maxtrigger $maxtrigger";
  Debug "retrigger $retrigger";

  if ($retrigger > 1)
  {
    my @commands;
    Log3 $name,5,"$name: maxtrigger: $maxtrigger";
    my $cmd = AttrVal($name,'HomeCMDcontactOpenWarning1','');
    $cmd = AttrVal($name,'HomeCMDcontactOpenWarning2','') if (AttrVal($name,'HomeCMDcontactOpenWarning2',undef) && $retrigger > 2);
    $cmd = AttrVal($name,'HomeCMDcontactOpenWarningLast','') if (AttrVal($name,'HomeCMDcontactOpenWarningLast',undef) && ($retrigger == int($maxtrigger+1) || ($maxtrigger == 0 && $retrigger == 1)));
    if ($cmd)
    {
      my $alias = name2alias($contact,1);
      my $openwarnct = int(@warn);
      my $openwarnhr = makeHR($hash,0,@warn);
      $cmd =~ s/%ALIAS%/$alias/xgm;
      $cmd =~ s/%SENSOR%/$contact/xgm;
      $cmd =~ s/%OPENWARN%/$openwarn/xg;
      $cmd =~ s/%OPENWARNCT%/$openwarnct/xg;
      $cmd =~ s/%OPENWARNHR%/$openwarnhr/xg;
      $cmd =~ s/%OPENWARNHR%/$openwarnhr/xg;
      $cmd =~ s/%UNIFIED%/$unified/xg;
      push @commands,$cmd;
    }
    execCMDs($hash,serializeCMD($hash,@commands)) if (@commands);
  }
  CommandDefine(undef,"$timer at +$waittime {fhem \"sleep 0.1 quiet;{FHEM::Automation::HOMEMODE::ContactOpenWarning('$name','$warn[0]',$retrigger)}\"}") if (!ID($timer) && $retrigger<=$maxtrigger);
  return;
}

sub ContactOpenWarningAfterModeChange
{
  my ($hash,$mode,$pmode,$resident) = @_;
  my $name = $hash->{NAME};
  my $contacts = ReadingsVal($name,'contactsOpen','');
  $mode = ReadingsVal($name,'mode','') if (!$mode);
  $pmode = ReadingsVal($name,'prevMode','') if (!$pmode);
  my $state = $resident?ReadingsVal($resident,'state',''):undef;
  my $pstate = $resident?ReadingsVal($resident,'lastState',''):undef;
  if ($contacts)
  {
    for (split /,/x,$contacts)
    {
      my $m = AttrVal($_,'HomeOpenDontTriggerModes','');
      my $r = AttrVal($_,'HomeOpenDontTriggerModesResidents','');
      $r = s/,/\|/xg;
      if ($resident && $m && $r && $resident =~ /^$r$/x && $state =~ /^$m$/x && $pstate !~ /^$m$/x)
      {
        ContactOpenWarning($name,$_);
      }
      elsif ($m && !$r && $pmode =~ /^$m$/x && $mode !~ /^$m$/x)
      {
        ContactOpenWarning($name,$_);
      }
    }
  }
  return;
}

sub ContactCommands
{
  my ($hash,$contact,$state,$kind) = @_;
  my $name = $hash->{NAME};
  my $alias = name2alias($contact,1);
  my @cmds;
  push @cmds,AttrVal($name,'HomeCMDcontact','') if (AttrVal($name,'HomeCMDcontact',undef));
  push @cmds,AttrVal($name,'HomeCMDcontactOpen','') if (AttrVal($name,'HomeCMDcontactOpen',undef) && $state eq 'open');
  push @cmds,AttrVal($name,'HomeCMDcontactClosed','') if (AttrVal($name,'HomeCMDcontactClosed',undef) && $state eq 'closed');
  push @cmds,AttrVal($name,'HomeCMDcontactDoormain','') if (AttrVal($name,'HomeCMDcontactDoormain',undef) && $kind eq 'doormain');
  push @cmds,AttrVal($name,'HomeCMDcontactDoormainOpen','') if (AttrVal($name,'HomeCMDcontactDoormainOpen',undef) && $kind eq 'doormain' && $state eq 'open');
  push @cmds,AttrVal($name,'HomeCMDcontactDoormainClosed','') if (AttrVal($name,'HomeCMDcontactDoormainClosed',undef) && $kind eq 'doormain' && $state eq 'closed');
  if (@cmds)
  {
    for (@cmds)
    {
      my ($c,$o) = split /\|/x,AttrVal($name,'HomeTextClosedOpen','closed|open');
      my $sta = $state eq 'open' ? $o : $c;
      $_ =~ s/%ALIAS%/$alias/xgm;
      $_ =~ s/%SENSOR%/$contact/xgm;
      $_ =~ s/%STATE%/$sta/xgm;
    }
    execCMDs($hash,serializeCMD($hash,@cmds));
  }
  return;
}

sub MotionCommands
{
  my ($hash,$sensor,$state) = @_;
  my $name = $hash->{NAME};
  my $alias = name2alias($sensor,1);
  my @cmds;
  push @cmds,AttrVal($name,'HomeCMDmotion','') if (AttrVal($name,'HomeCMDmotion',undef));
  push @cmds,AttrVal($name,'HomeCMDmotion-on','') if (AttrVal($name,'HomeCMDmotion-on',undef) && $state eq 'open');
  push @cmds,AttrVal($name,'HomeCMDmotion-off','') if (AttrVal($name,'HomeCMDmotion-off',undef) && $state eq 'closed');
  if (@cmds)
  {
    for (@cmds)
    {
      my ($c,$o) = split /\|/x,AttrVal($name,'HomeTextClosedOpen','closed|open');
      $state = $state eq 'open' ? $o : $c;
      $_ =~ s/%ALIAS%/$alias/xgm;
      $_ =~ s/%SENSOR%/$sensor/xgm;
      $_ =~ s/%STATE%/$state/xgm;
    }
    execCMDs($hash,serializeCMD($hash,@cmds));
  }
  return;
}

sub EventCommands
{
  my ($hash,$cal,$read,$event) = @_;
  my $name = $hash->{NAME};
  my $prevevent = ReadingsVal($name,"event-$cal",'');
  my @cmds;
  if ($read ne 'modeStarted')
  {
    push @cmds,AttrVal($name,'HomeCMDevent','') if (AttrVal($name,'HomeCMDevent',undef));
    push @cmds,AttrVal($name,"HomeCMDevent-$cal-each",'') if (AttrVal($name,"HomeCMDevent-$cal-each",undef));
  }
  if (ID($cal,'holiday'))
  {
    if ($event ne $prevevent)
    {
      $event =~ s/[,;:\?\!\|\\\/\^\$]/-/xg;
      my $evt = $event;
      $evt =~ s/[\s ]+/-/g;
      my $pevt = $prevevent;
      $pevt =~ s/[\s ]+/-/g;
      push @cmds,AttrVal($name,"HomeCMDevent-$cal-".makeReadingName($pevt).'-end','') if (AttrVal($name,"HomeCMDevent-$cal-".makeReadingName($pevt).'-end',undef));
      push @cmds,AttrVal($name,"HomeCMDevent-$cal-".makeReadingName($evt).'-begin','') if (AttrVal($name,"HomeCMDevent-$cal-".makeReadingName($evt).'-begin',undef));
      readingsSingleUpdate($hash,"event-$cal",$event,1);
      for (@cmds)
      {
        $_ =~ s/%EVENT%/$event/xgm;
        $_ =~ s/%PREVEVENT%/$prevevent/xgm;
      }
    }
  }
  else
  {
    my @prevevents;
    @prevevents = split /,/x,$prevevent if ($prevevent ne 'none');
    for (split /;/x,$event)
    {
      $event =~ s/[\s ]//g;
      my $summary;
      my $description = '';
      my $t = time();
      my @filters = ( { ref => \&filter_true, param => undef } );
      for (Calendar_GetEvents($defs{$cal},$t,@filters))
      {
        next unless ($_->{uid} eq $event);
        $summary = $_->{summary};
        $description = $_->{description};
        last;
      }
      next unless $summary;
      $summary =~ s/[,;:\?\!\|\\\/\^\$]/-/xg;
      Log3 $name,5,"Calendar_GetEvents event: $summary";
      my $sum = $summary;
      $sum =~ s/[\s ]+/-/g;
      if ($read eq 'start')
      {
        push @prevevents,$summary;
        push @cmds,AttrVal($name,"HomeCMDevent-$cal-".makeReadingName($sum).'-begin','') if (AttrVal($name,"HomeCMDevent-$cal-".makeReadingName($sum).'-begin',undef));
      }
      elsif ($read eq 'end')
      {
        push @cmds,AttrVal($name,"HomeCMDevent-$cal-".makeReadingName($sum).'-end','') if (AttrVal($name,"HomeCMDevent-$cal-".makeReadingName($sum).'-end',undef));
        if (grep {$_ eq $summary} @prevevents)
        {
          my @sevents;
          for (@prevevents)
          {
            push @sevents,$_ if ($_ ne $summary);
          }
          @prevevents = @sevents;
        }
      }
      elsif ($read eq 'modeStarted')
      {
        push @prevevents,$summary;
      }
      for (@cmds)
      {
        if ($read eq 'start')
        {
          $_ =~ s/%EVENT%/$summary/xgm;
          $_ =~ s/%PREVEVENT%/none/xgm;
          $_ =~ s/%DESCRIPTION%/$description/xgm;
        }
        elsif ($read eq 'end')
        {
          $_ =~ s/%EVENT%/none/xgm;
          $_ =~ s/%PREVEVENT%/$summary/xgm;
          $_ =~ s/%DESCRIPTION%/$description/xgm;
        }
      }
    }
    my $update = 'none';
    if (@prevevents)
    {
      @prevevents = uniq sort @prevevents;
      $update = join ',',@prevevents;
    readingsSingleUpdate($hash,"event-$cal",$update,1);
    }
  }
  for (@cmds)
  {
    $_ =~ s/%CALENDAR%/$cal/xgm;
  }
  execCMDs($hash,serializeCMD($hash,@cmds)) if (@cmds);
  return;
}

sub UWZCommands
{
  my ($hash,$events) = @_;
  my $name = $hash->{NAME};
  my $prev = ReadingsNum($name,'uwz_warnCount',-1);
  my $uwz = AttrVal($name,'HomeUWZ','');
  my $count;
  for my $evt (@{$events})
  {
    next unless (grep {/^WarnCount:\s[0-9]$/} $evt);
    $count = $evt;
    $count =~ s/^WarnCount:\s//;
    last;
  }
  if (defined $count)
  {
    readingsSingleUpdate($hash,'uwz_warnCount',$count,1);
    if ($count != $prev)
    {
      my $se = $count > 0 ? 'begin':'end';
      my @cmds;
      push @cmds,AttrVal($name,'HomeCMDuwz-warn','') if (AttrVal($name,'HomeCMDuwz-warn',undef));
      push @cmds,AttrVal($name,"HomeCMDuwz-warn-$se",'') if (AttrVal($name,"HomeCMDuwz-warn-$se",undef));
      execCMDs($hash,serializeCMD($hash,@cmds)) if (@cmds);
    }
  }
  return;
}

sub HomebridgeMapping
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $mapping = 'SecuritySystemCurrentState=alarmState,values=armhome:0;armaway:1;armnight:2;disarm:3;alarm:4';
  $mapping .= '\nSecuritySystemTargetState=modeAlarm,values=armhome:0;armaway:1;armnight:2;disarm:3,cmds=0:modeAlarm+armhome;1:modeAlarm+armaway;2:modeAlarm+armnight;3:modeAlarm+disarm,delay=1';
  $mapping .= '\nSecuritySystemAlarmType=alarmTriggered_ct,values=0:0;/.*/:1';
  $mapping .= '\nOccupancyDetected=presence,values=present:1;absent:0';
  $mapping .= '\nMute=dnd,valueOn=on,cmdOn=dnd+on,cmdOff=dnd+off';
  $mapping .= '\nOn=anyoneElseAtHome,valueOn=on,cmdOn=anyoneElseAtHome+on,cmdOff=anyoneElseAtHome+off';
  $mapping .= '\nContactSensorState=contactsOutsideOpen_ct,values=0:0;/.*/:1' if (ID($name,undef,'contactsOutsideOpen_ct'));
  $mapping .= '\nStatusTampered=alarmTampered_ct,values=0:0;/.*/:1' if (ID($name,undef,'alarmTampered_ct'));
  $mapping .= '\nMotionDetected=motionsInside_ct,values=0:0;/.*/:1' if (ID($name,undef,'motionsInside_ct'));
  $mapping .= '\nStatusLowBattery=batteryLow_ct,values=0:0;/.*/:1' if (ID($name,undef,'batteryLow_ct'));
  $mapping .= '\nSmokeDetected=alarmSmoke_ct,values=0:0;/.*/:1' if (ID($name,undef,'alarmSmoke_ct'));
  $mapping .= '\nLeakDetected=alarmWater_ct,values=0:0;/.*/:1' if (ID($name,undef,'alarmWater_ct'));
  $mapping .= '\nAirPressure=pressure' if (ID($name,undef,'pressure'));
  addToDevAttrList($name,'genericDeviceType') if (!grep {/^genericDeviceType/x} split ' ',AttrVal('global','userattr',''));
  addToDevAttrList($name,'homebridgeMapping:textField-long') if (!grep {/^homebridgeMapping/x} split ' ',AttrVal('global','userattr',''));
  CommandAttr(undef,"$name genericDeviceType security");
  CommandAttr(undef,"$name homebridgeMapping $mapping");
  return;
}

sub EnergyPower
{
  my ($hash,$ep) = @_;
  my $name = $hash->{NAME};
  my $val = 0;
  my @sensors = split /,/x,InternalVal($name,'SENSORS'.uc($ep),'');
  for (@sensors)
  {
    my $r = AttrVal($_,'HomeReading'.$ep,AttrVal($name,'HomeSensors'.$ep.'Reading',lc($ep)));
    my $d = AttrVal($_,'HomeDivider'.$ep,AttrVal($name,'HomeSensors'.$ep.'Divider',1));
    $d = $d && $d =~ /^(?!0)\d+(\.\d+)?$/?$d:1;
    my $e = ReadingsNum($_,$r,0);
    if ($e)
    {
      if (AttrVal($_,'HomeAllowNegative'.$ep,0))
      {
        $val += $e/$d;
      }
      else
      {
        $val += $e if (sprintf('%.2f',$e/$d)>0);
      }
    }
  }
  $val = sprintf('%.2f',$val); 
  readingsSingleUpdate($hash,lc($ep),$val,1);
  readingsSingleUpdate($hash,lc($ep).'_avg',sprintf('%.2f',($val/int(@sensors))),1);
  return;
}

sub twoStateSensor
{
  my ($hash,$type,$trigger,$state) = @_;
  my $name = $hash->{NAME};
  my @sensors;
  my $internal = 'SENSORS'.uc $type;
  my $v;
  for (split /,/x,InternalVal($name,$internal,''))
  {
    my $s = $type eq 'Tamper'?'sabotageError':'state';
    my $r = AttrVal($_,"HomeReading$type",AttrVal($name,'HomeSensors'.$type.'Reading',$s));
    $v = AttrVal($_,"HomeValue$type",AttrVal($name,'HomeSensors'.$type.'Value',lc $type.'|open|on|yes|1|true'));
    push @sensors,$_ if (ReadingsVal($_,$r,'') =~ /^$v$/x);
  }
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"alarm$type",join(',',@sensors));
  readingsBulkUpdate($hash,'alarm'.$type.'_ct',int(@sensors));
  readingsBulkUpdate($hash,'alarm'.$type.'_hr',makeHR($hash,0,@sensors));
  readingsEndUpdate($hash,1);
  if ($trigger && $state)
  {
    my $t = "$type$type";
    my $no = 'no';
    my $ty = $type;
    if ($type eq 'Tamper')
    {
      $ty .= 'ed';
      $no .= 't';
    }
    my @cmds;
    push @cmds,AttrVal($name,'HomeCMDalarm'.$ty,'') if (AttrVal($name,'HomeCMDalarm'.$ty,''));
    if (@sensors)
    {
      push @cmds,AttrVal($name,'HomeCMDalarm'.$ty.'-on','') if (AttrVal($name,'HomeCMDalarm'.$ty.'-on',''));
    }
    else
    {
      push @cmds,AttrVal($name,'HomeCMDalarm'.$ty.'-off','') if (AttrVal($name,'HomeCMDalarm'.$ty.'-off',''));
    }
    for (@cmds)
    {
      my $alias = name2alias($trigger,1);
      $_ =~ s/%ALIAS%/$alias/xgm;
      $_ =~ s/%SENSOR%/$trigger/xgm;
      my ($n,$s) = split /\|/x,AttrVal($name,"HomeTextNo$t","$no ".lc $ty.'|'.lc $ty);
      my $sta = $state =~ /^$v$/x ? $s : $n;
      $_ =~ s/%STATE%/$sta/xgm;
      my $no = '%'.uc $ty.'%';
      my $nor = join(',',@sensors);
      my $ct = '%'.uc $ty.'CT%';
      my $ctr = int(@sensors);
      my $hr = '%'.uc $ty.'HR%';
      my $hrr = makeHR($hash,0,@sensors);
      $_ =~ s/$no/$nor/xgm;
      $_ =~ s/$ct/$ctr/xgm;
      $_ =~ s/$hr/$hrr/xgm;
    }
    execCMDs($hash,serializeCMD($hash,@cmds)) if (@cmds);
  }
  return;
}

sub Weather
{
  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};
  my $cond = ReadingsVal($dev,'condition','');
  my ($and,$are,$is) = split /\|/x,AttrVal($name,'HomeTextAndAreIs','and|are|is');
  my $be = $cond =~ /(und|and|[Gg]ewitter|[Tt]hunderstorm|[Ss]chauer|[Ss]hower)/x ? $are : $is;
  my $wl = WeatherTXT($hash,AttrVal($name,'HomeTextWeatherLong',''));
  my $ws = WeatherTXT($hash,AttrVal($name,'HomeTextWeatherShort',''));
  my $wf = ForecastTXT($hash);
  my $wf1 = ForecastTXT($hash,1);
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,'humidity',ReadingsNum($dev,'humidity',5)) if ((!AttrVal($name,'HomeSensorTemperatureOutside',undef) || (AttrVal($name,'HomeSensorTemperatureOutside',undef) && !ID(AttrVal($name,'HomeSensorTemperatureOutside',undef),'.*','humidity'))) && !AttrVal($name,'HomeSensorHumidityOutside',undef));
  readingsBulkUpdate($hash,'temperature',ReadingsNum($dev,'temperature',5)) if (!AttrVal($name,'HomeSensorTemperatureOutside',undef));
  readingsBulkUpdate($hash,'wind',ReadingsNum($dev,'wind',0)) if (!AttrVal($name,'HomeSensorWindspeed',undef));
  readingsBulkUpdate($hash,'pressure',ReadingsNum($dev,'pressure',5)) if (!AttrVal($name,'HomeSensorAirpressure',undef));
  readingsBulkUpdate($hash,'weatherTextLong',$wl);
  readingsBulkUpdate($hash,'weatherTextShort',$ws);
  readingsBulkUpdate($hash,'weatherTextForecastToday',$wf1);
  readingsBulkUpdate($hash,'weatherTextForecastTomorrow',$wf);
  readingsBulkUpdate($hash,'.be',$be);
  readingsEndUpdate($hash,1);
  ReadingTrend($hash,'humidity') if (!AttrVal($name,'HomeSensorHumidityOutside',undef));
  ReadingTrend($hash,'temperature') if (!AttrVal($name,'HomeSensorTemperatureOutside',undef));
  ReadingTrend($hash,'pressure') if (!AttrVal($name,'HomeSensorAirpressure',undef));
  Icewarning($hash);
  return;
}

sub Twilight
{
  my ($hash,$dev,$force) = @_;
  my $name = $hash->{NAME};
  my $events = deviceEvents($defs{$dev},1);
  if ($force)
  {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,'light',ReadingsVal($dev,'light',5));
    readingsBulkUpdate($hash,'twilight',ReadingsVal($dev,'twilight',5));
    readingsBulkUpdate($hash,'twilightEvent',ReadingsVal($dev,'aktEvent',5));
    readingsEndUpdate($hash,1);
  }
  else
  {
    my $pevent = ReadingsVal($name,'twilightEvent','');
    for my $event (@{$events})
    {
      my $val = (split ' ',$event)[1];
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,'light',$val) if ($event =~ /^light:/x);
      readingsBulkUpdate($hash,'twilight',$val) if ($event =~ /^twilight:/x);
      if ($event =~ /^aktEvent:/x)
      {
        readingsBulkUpdate($hash,'twilightEvent',$val);
        if ($val ne $pevent)
        {
          my @commands;
          push @commands,AttrVal($name,'HomeCMDtwilight','') if (AttrVal($name,'HomeCMDtwilight',undef));
          push @commands,AttrVal($name,"HomeCMDtwilight-$val",'') if (AttrVal($name,"HomeCMDtwilight-$val",undef));
          execCMDs($hash,serializeCMD($hash,@commands)) if (@commands);
        }
      }
      readingsEndUpdate($hash,1);
    }
  }
  return;
}

sub Icewarning
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $ice = ReadingsVal($name,'icewarning',2);
  my $temp = ReadingsVal($name,'temperature',5);
  my $temps = AttrVal($name,'HomeIcewarningOnOffTemps','2 3');
  my $iceon = (split ' ',$temps)[0] * 1;
  my $iceoff = (split ' ',$temps)[1] ? (split ' ',$temps)[1] * 1 : $iceon;
  my $icewarning = 0;
  my $icewarningcmd = 'off';
  $icewarning = 1 if ((!$ice && $temp <= $iceon) || ($ice && $temp <= $iceoff));
  $icewarningcmd = 'on' if ($icewarning == 1);
  if ($ice != $icewarning)
  {
    my @commands;
    push @commands,AttrVal($name,'HomeCMDicewarning','') if (AttrVal($name,'HomeCMDicewarning',undef));
    push @commands,AttrVal($name,"HomeCMDicewarning-$icewarningcmd",'') if (AttrVal($name,"HomeCMDicewarning-$icewarningcmd",undef));
    readingsSingleUpdate($hash,'icewarning',$icewarning,1);
    execCMDs($hash,serializeCMD($hash,@commands)) if (@commands);
  }
  return;
}

sub CalendarEvents
{
  my ($name,$cal) = @_;
  my $hash = $defs{$name};
  my $filt = AttrCheck($hash,'HomeEventsFilter-'.$cal,'');
  my @events;
  if (ID($cal,'holiday'))
  {
    my (undef,@holidaylines) = FileRead(InternalVal($cal,'HOLIDAYFILE',''));
    for (@holidaylines)
    {
      next unless ($_ =~ /^[1234]\s/);
      my @parts = split;
      my $part = $parts[0] =~ /^[12]$/x ? 2 : $parts[0] == 3 ? 4 : $parts[0] == 4 ? 3 : 5;
      for (my $p = 0; $p < $part; $p++)
      {
        shift @parts;
      }
      my $evt = join('-',@parts);
      if ($filt)
      {
        push @events,$evt if ($evt =~ /^$filt$/);
      }
      else
      {
        push @events,$evt;
      }
    }
  }
  else
  {
    my $t = time();
    my @filters = ( { ref => \&filter_true, param => undef } );
    for (Calendar_GetEvents($defs{$cal},$t,@filters))
    {
      my $evt = $_->{summary};
      Log3 $name,5,"Calendar_GetEvents event: $evt";
      $evt =~ s/[,;:\?\!\|\\\/\^\$\s ]/-/g;
      if ($filt)
      {
        push @events,$evt if ($evt =~ /^$filt$/);
      }
      else
      {
        push @events,$evt;
      }
    }
  }
  @events = uniq @events;
  return \@events;
}

sub checkIP
{
  my ($hash) = @_;
  return if ($hash->{helper}{RUNNING_IPCHECK});
  $hash->{helper}{RUNNING_IPCHECK} = 1;
  my $param = {
    url        => 'http://icanhazip.com/',
    timeout    => 5,
    hash       => $hash,
    callback   => \&FHEM::Automation::HOMEMODE::setIP
  };
  return HttpUtils_NonblockingGet($param);
}

sub setIP
{
  my ($param,$err,$data) = @_;
  my $hash = $param->{hash};
  delete $hash->{helper}{RUNNING_IPCHECK};
  my $name = $hash->{NAME};
  if ($err ne '')
  {
    Log3 $name,3,"$name: Error while requesting ".$param->{url}." - $err";
  }
  if (!$data || $data =~ /[<>]/x)
  {
    $err = 'Error - publicIP service check is temporary not available';
    readingsSingleUpdate($hash,'publicIP',$err,1);
    Log3 $name,3,"$name: $err";
  }
  elsif ($data ne '')
  {
    $data =~ s/\s+//g;
    chomp $data;
    if (ReadingsVal($name,'publicIP','') ne $data)
    {
      my @commands;
      readingsSingleUpdate($hash,'publicIP',$data,1);
      push @commands,AttrVal($name,'HomeCMDpublic-ip-change','') if (AttrVal($name,'HomeCMDpublic-ip-change',undef));
      execCMDs($hash,serializeCMD($hash,@commands)) if (@commands);
    }
  }
  if (AttrNum($name,'HomePublicIpCheckInterval',0))
  {
    my $timer = gettimeofday() + 60 * AttrNum($name,'HomePublicIpCheckInterval',0);
    $hash->{'.IP_TRIGGERTIME_NEXT'} = $timer;
  }
  return;
}

sub ToggleDevice
{
  my ($hash,$devname) = @_;
  my $name = $hash->{NAME};
  my @disabled;
  @disabled = split /,/x,ReadingsVal($name,'devicesDisabled','') if (ReadingsVal($name,'devicesDisabled',''));
  if ($devname)
  {
    my @cmds;
    if (grep {$_ eq $devname} @disabled)
    {
      push @cmds,AttrVal($name,'HomeCMDdeviceEnable','') if (AttrVal($name,'HomeCMDdeviceEnable',''));
      my @new;
      for (@disabled)
      {
        push @new,$_ if ($_ ne $devname);
      }
      @disabled = @new;
    }
    else
    {
      push @cmds,AttrVal($name,'HomeCMDdeviceDisable','') if (AttrVal($name,'HomeCMDdeviceDisable',''));
      push @disabled,$devname;
    }
    my $dis = @disabled?join(',',@disabled):'';
    readingsSingleUpdate($hash,'devicesDisabled',$dis,1);
    if (@cmds)
    {
      for (@cmds)
      {
        my $a = name2alias($devname);
        $_ =~ s/%ALIAS%/$a/xgm;
        $_ =~ s/%DEVICE%/$devname/xgm;
      }
      execCMDs($hash,serializeCMD($hash,@cmds));
    }
  }
  my @list;
  for my $d (split /,/x,$hash->{NOTIFYDEV})
  {
    push @list,$d if (!grep {$_ eq $d} @disabled);
  }
  $hash->{helper}{enabledDevices} = join ',',@list;
  return;
}

sub IsDis
{
  my ($name,$devname) = @_;
  $devname = $devname?$devname:$name;
  return 1 if (IsDisabled($devname));
  return 1 if (grep {$_ eq $devname} split /,/x,ReadingsVal($name,'devicesDisabled',''));
  return 0;
}

sub Details
{
  my (undef,$name,$room) = @_;
  my $hash = $defs{$name};
  my @batteries;
  my @contacts;
  my @energies;
  my @lights;
  my @motions;
  my @powers;
  my @smokes;
  my @tampers;
  my @waters;
  my $text;
  for my $s (split /,/x,$hash->{NOTIFYDEV})
  {
    push @batteries,$s if (grep {$_ eq $s} split /,/x,InternalVal($name,'SENSORSBATTERY',''));
    push @contacts,$s if (grep {$_ eq $s} split /,/x,InternalVal($name,'SENSORSCONTACT',''));
    push @energies,$s if (grep {$_ eq $s} split /,/x,InternalVal($name,'SENSORSENERGY',''));
    push @lights,$s if (grep {$_ eq $s} split /,/x,InternalVal($name,'SENSORSLIGHT',''));
    push @motions,$s if (grep {$_ eq $s} split /,/x,InternalVal($name,'SENSORSMOTION',''));
    push @powers,$s if (grep {$_ eq $s} split /,/x,InternalVal($name,'SENSORSPOWER',''));
    push @smokes,$s if (grep {$_ eq $s} split /,/x,InternalVal($name,'SENSORSSMOKE',''));
    push @tampers,$s if (grep {$_ eq $s} split /,/x,InternalVal($name,'SENSORSTAMPER',''));
    push @waters,$s if (grep {$_ eq $s} split /,/x,InternalVal($name,'SENSORSWATER',''));
  }
  # Start HTML
  my $html = '<style type="text/css">@import url("./fhem/www/pgm2/homemode.css");</style>';
  my $usercss = AttrVal($name,'HomeUserCSS','');
  $html .= "<style>$usercss</style>" if ($usercss);
  $html .= '<table id="HOMEMODE" class="wide" devname="'.$name.'" lang="'.AttrVal($name,'HomeLanguage',AttrVal('global','language','EN')).'">';
  $html .= '<tbody>';
  if (AttrVal($name,'HomeAdvancedDetails','none') eq 'none' || (AttrVal($name,'HomeAdvancedDetails','') eq 'room' && $FW_detail eq $name))
  {
    ###
  }
  else 
  {
    my $iid = ReadingsVal($name,'.lastInfo','');
    $html .= '<tr>';
    $html .= '<td class="HOMEMODE_details">';
    $html .= '<table class="wide">';
    $html .= '<tbody>';
    if (AttrVal($name,'HomeWeatherDevice','') ||
       (AttrVal($name,'HomeSensorAirpressure','') && AttrVal($name,'HomeSensorHumidityOutside','') && AttrVal($name,'HomeSensorTemperatureOutside','')) ||
       (AttrVal($name,'HomeSensorAirpressure','') && AttrVal($name,'HomeSensorTemperatureOutside','') && ID(AttrVal($name,'HomeSensorTemperatureOutside',''),undef,'humidity')))
    {
      $html .= '<tr class="HOMEMODE_i">';
      $text = $langDE?'Temperatur':'Temperature';
      $html .= '<td class="HOMEMODE_tar">'.$text.':</td>';
      $text = $langDE?'Wettervorhersage':'Weather forecast';
      $html .= '<td class="dval"><span informid="'.$name.'-temperature">'.ReadingsNum($name,'temperature','').'</span> °C<span class="HOMEMODE_info" informid="'.$name.'-weatherTextForecastToday" header="'.$text.'">'.ReadingsVal($name,'weatherTextForecastToday','<NO FORECAST AVAILABLE>').'</span></td>';
      $text = $langDE?'Luftfeuchte':'Humidity';
      $html .= '<td class="HOMEMODE_tar">'.$text.':</td>';
      $html .= '<td class="dval"><span informid="'.$name.'-humidity">'.ReadingsNum($name,'humidity','').'</span> %</td>';
      $text = $langDE?'Luftdruck':'Air pressure';
      $html .= '<td class="HOMEMODE_tar">'.$text.':</td>';
      $html .= '<td class="dval"><span informid="'.$name.'-pressure">'.ReadingsNum($name,'pressure','').'</span> hPa</td>';
      $html .= '</tr>';
    }
    if (int(@powers) || int(@energies) || int(@lights))
    {
      $html .= '<tr>';
      $text = $langDE?'Leistung':'Power';
      $html .= '<td class="HOMEMODE_tar">'.$text.':</td>';
      $html .= '<td class="dval">';
      $html .= int(@powers)?'<span informid="'.$name.'-power">'.ReadingsNum($name,'power',0).'</span> W':'-';
      $html .= '</td>';
      $text = $langDE?'Verbrauch':'Energy';
      $html .= '<td class="HOMEMODE_tar">'.$text.':</td>';
      $html .= '<td class="dval">';
      $html .= int(@energies)?'<span informid="'.$name.'-energy">'.ReadingsNum($name,'energy',0).'</span> kWh':'-';
      $html .= '</td>';
      $text = $langDE?'Licht':'Light';
      $html .= '<td class="HOMEMODE_tar">'.$text.':</td>';
      $html .= '<td class="dval">';
      $html .= int(@lights)?'<span informid="'.$name.'-luminance">'.ReadingsNum($name,'luminance',0).'</span> lux':'-';
      $html .= '</td>';
      $html .= '</tr>';
    }
    if (int(@contacts))
    {
      $html .= '<tr>';
      $text = $langDE?'Offen':'Open';
      $html .= '<td class="HOMEMODE_tar">'.$text.':</td>';
      $html .= '<td class="dval HOMEMODE_i">';
      $text = $langDE?'Offene Kontakte':'Open contacts';
      $html .= int(@contacts)?'<span informid="'.$name.'-contactsOpen_ct">'.ReadingsNum($name,'contactsOpen_ct',0).'</span><span class="HOMEMODE_info" informid="'.$name.'-contactsOpen_hr" header="'.$text.'">'.ReadingsVal($name,'contactsOpen_hr','-').'</span>':'-';
      $html .= '</td>';
      $text = $langDE?'Offen-Warnungen':'Open warnings';
      $html .= '<td class="HOMEMODE_tar">'.$text.':</td>';
      $html .= '<td class="dval HOMEMODE_i">';
      $text = $langDE?'Aktive Offen-Warnungen':'Active open warnings';
      $html .= int(@contacts)?'<span informid="'.$name.'-contactWarning_ct">'.ReadingsNum($name,'contactWarning_ct',0).'</span><span class="HOMEMODE_info" informid="'.$name.'-contactWarning_hr" header="'.$text.'">'.ReadingsVal($name,'contactWarning_hr','-').'</span>':'-';
      $html .= '</td>';
      $html .= '<td class="HOMEMODE_tar">'.($langDE?'Abgel. Offen-Warnungen':'Expired open warnings').':</td>';
      $html .= '<td class="dval HOMEMODE_i">';
      $text = $langDE?'Abgelaufene Offen-Warnungen':'Expired open warnings';
      $html .= '<span informid="'.$name.'-contactWarningExpired_ct">'.ReadingsNum($name,'contactWarningExpired_ct',0).'</span><span class="HOMEMODE_info" informid="'.$name.'-contactWarningExpired_hr" header="'.$text.'">'.ReadingsVal($name,'contactWarningExpired_hr','-').'</span>';
      $html .= '</td>';
      $html .= '</tr>';
    }
    if (int(@batteries) || int(@smokes) || int(@tampers))
    {
      $html .= '<tr>';
      $text = $langDE?ReadingsNum($name,'batteryLow_ct',0) == 1 ? 'Batterie leer':'Batterien leer' : ReadingsNum($name,'batteryLow_ct',0) == 1 ? 'Battery empty':'Batteries empty';
      $html .= '<td class="HOMEMODE_tar">'.$text.':</td>';
      $html .= '<td class="dval HOMEMODE_i">';
      $text = $langDE?'Niedrige Batteriestände':'Low batteries';
      $html .= int(@batteries)?'<span informid="'.$name.'-batteryLow_ct">'.ReadingsNum($name,'batteryLow_ct',0).'</span><span class="HOMEMODE_info" informid="'.$name.'-batteryLow_hr" header="'.$text.'">'.ReadingsVal($name,'batteryLow_hr','-').'</span>':'-';
      $html .= '</td>';
      $text = $langDE?'Rauch':'Smoke';
      $html .= '<td class="HOMEMODE_tar">'.$text.':</td>';
      $html .= '<td class="dval HOMEMODE_i">';
      $text = $langDE?'Aktive Rauch/Feuer Alarme':'Active smoke/fire alarms';
      $html .= int(@smokes)?'<span informid="'.$name.'-alarmSmoke_ct">'.ReadingsNum($name,'alarmSmoke_ct',0).'</span><span class="HOMEMODE_info" informid="'.$name.'-alarmSmoke_hr" header="'.$text.'">'.ReadingsVal($name,'alarmSmoke_hr','-').'</span>':'-';
      $html .= '</td>';
      $text = $langDE?'Sabotiert':'Tampered';
      $html .= '<td class="HOMEMODE_tar">'.$text.':</td>';
      $html .= '<td class="dval HOMEMODE_i">';
      $text = $langDE?'Aktive Sabotagealarme':'Active tamper alarms';
      $html .= int(@tampers)?'<span informid="'.$name.'-alarmTamper_ct">'.ReadingsNum($name,'alarmTamper_ct',0).'</span><span class="HOMEMODE_info" informid="'.$name.'-alarmTamper_hr" header="'.$text.'">'.ReadingsVal($name,'alarmTamper_hr','-').'</span>':'-';
      $html .= '</td>';
      $html .= '</tr>';
    }
    if (int(@waters) || int(@motions) || int(@contacts))
    {
      $html .= '<tr>';
      $text = $langDE?'Wasser':'Water';
      $html .= '<td class="HOMEMODE_tar">'.$text.':</td>';
      $html .= '<td class="dval HOMEMODE_i">';
      $text = $langDE?'Aktive Wasseralarme':'Active water alarms';
      $html .= int(@waters)?'<span informid="'.$name.'-alarmWater_ct">'.ReadingsNum($name,'alarmWater_ct',0).'</span><span class="HOMEMODE_info" informid="'.$name.'-alarmWater_hr" header="'.$text.'">'.ReadingsVal($name,'alarmWater_hr','-').'</span>':'-';
      $html .= '</td>';
      $text = $langDE?'Bewegung':'Motion';
      $html .= '<td class="HOMEMODE_tar">'.$text.':</td>';
      $html .= '<td class="dval HOMEMODE_i">';
      $text = $langDE?'Aktive Bewegungen':'Active motions';
      $html .= int(@motions)?'<span informid="'.$name.'-motionsSensors_ct">'.ReadingsNum($name,'motionsSensors_ct',0).'</span><span class="HOMEMODE_info" informid="'.$name.'-motionsSensors_hr" header="'.$text.'">'.ReadingsVal($name,'motionsSensors_hr','-').'</span>':'-';
      $html .= '</td>';
      $html .= '<td class="HOMEMODE_tar">Alarm:</td>';
      $html .= '<td class="dval HOMEMODE_i">';
      $text = $langDE?'Aktive Alarme':'Active alarms';
      $html .= '<span informid="'.$name.'-alarmTriggered_ct">'.ReadingsNum($name,'alarmTriggered_ct',0).'</span><span class="HOMEMODE_info" informid="'.$name.'-alarmTriggered_hr" header="'.$text.'">'.ReadingsVal($name,'alarmTriggered_hr','-').'</span>';
      $html .= '</td>';
      $html .= '</tr>';
    }
    $html .= '</tbody>';
    $html .= '</table>';
    $html .= '</td>';
    $html .= '</tr>';
    $html .= '<tr>';
    $html .= '<td>';
    $html .= '<h4 id="HOMEMODE_infopanelh">';
    $html .= ($langDE?'Anzeige von detaillierten Informationen':'Display of detailed informations').'</h4>';
    $html .= '</td>';
    $html .= '</tr>';
    $html .= '<tr>';
    $html .= '<td id="HOMEMODE_infopanel" informid="'.$name.'-'.$iid.'">';
    $text = $langDE?'Bisher wurden keine anzuzeigenden Informationen ausgewählt':'No informations to display have been chosen so far';
    $html .= $text;
    $html .= '</td>';
    $html .= '</tr>';
  }
  if ($FW_detail eq $name)
  {
    my $deact = $langDE?'Verarbeitung der Events des Geräts inneralb von HOMEMODE deaktivieren':'Deactivate processing of this device´s events within HOMEMODE';
    my $sensor = $langDE?'Sensorname':'Sensor name';
    $hash->{helper}{inDetails} = 1;
    if (@batteries || @contacts || @energies || @lights || @motions || @powers || @smokes || @tampers || @waters)
    {
      $html .= '<tr>';
      $html .= '<td>';
      $text = $langDE?'Konfiguration der überwachten Sensoren':'Configuration of monitored sensors';
      $html .= "<h4>$text</h4>";
      $html .= '</td>';
      $html .= '</tr>';
      $html .= '<tr>';
      $html .= '<td id="HOMEMODE-buttons">';
      $text = $langDE?'Batterien':'Batteries';
      $html .= '<button class="HOMEMODE_button" id="HOMEMODE-Battery">'.$text.'</button>' if (@batteries);
      $text = $langDE?'Kontakte':'Contacts';
      $html .= '<button class="HOMEMODE_button" id="HOMEMODE-Contact">'.$text.'</button>' if (@contacts);
      $text = $langDE?'Verbrauchsmesser':'Energy sensors';
      $html .= '<button class="HOMEMODE_button" id="HOMEMODE-Energy">'.$text.'</button>' if (@energies);
      $text = $langDE?'Lichtmesser':'Light sensors';
      $html .= '<button class="HOMEMODE_button" id="HOMEMODE-Luminance">'.$text.'</button>' if (@lights);
      $text = $langDE?'Bewegungsmelder':'Motion sensors';
      $html .= '<button class="HOMEMODE_button" id="HOMEMODE-Motion">'.$text.'</button>' if (@motions);
      $text = $langDE?'Leistungsmesser':'Power sensors';
      $html .= '<button class="HOMEMODE_button" id="HOMEMODE-Power">'.$text.'</button>' if (@powers);
      $text = $langDE?'Rauchmelder':'Smoke sensors';
      $html .= '<button class="HOMEMODE_button" id="HOMEMODE-Smoke">'.$text.'</button>' if (@smokes);
      $text = $langDE?'Sabotagekontakte':'Tamper sensors';
      $html .= '<button class="HOMEMODE_button" id="HOMEMODE-Tamper">'.$text.'</button>' if (@tampers);
      $text = $langDE?'Wassermelder':'Water sensors';
      $html .= '<button class="HOMEMODE_button" id="HOMEMODE-Water">'.$text.'</button>' if (@waters);
      $html .= '</td>';
      $html .= '</tr>';
    }
    $html .= '<tr>';
    $html .= '<td>';
    $html .= '<form method="get" action="">';
    if (@batteries)
    {
      $html .= '<table class="block HOMEMODE_table" id="HOMEMODE-Battery-table">';
      $html .= '<thead>';
      $html .= '<tr>';
      $html .= '<th><abbr title="'.$deact.'">#</abbr></th>';
      # $text = $langDE?'Füge neue Batteriesensoren hinzu (kommaseparierte Liste)':'Add new battery sensors (comma separated list)';
      # $html .= '<th>'.$sensor.' <button class="add" title="'.$text.'">+</button></th>';
      $html .= '<th>'.$sensor.'</th>';
      $text = $langDE?'Name des Reading welches den Batteriewert anzeigt':'Name of the reading indicating the battery value';
      $html .= '<th><abbr title="'.$text.'">Home<br>ReadingBattery</abbr></th>';
      $text = $langDE?'Prozentwert des Batteriereading ab dem eine Batteriestandswarnung ausgelöst werden soll':'Percentage of the value of the battery reading to trigger battery low warning';
      $html .= '<th><abbr title="'.$text.'">Home<br>BatteryLowPercentage</abbr></th>';
      $html .= '</tr>';
      $html .= '</thead>';
      $html .= '<tbody>';
      my $c = 1;
      for my $s (sort @batteries)
      {
        my $alias = AttrVal($s,'alias','');
        $html .= '<tr';
        $html .= ' class="';
        $html .= $c%2?'odd':'even';
        $html .= '">';
        $html .= '<td>';
        $html .= '<label><input type="checkbox" name="HomeActive" value="" title="'.$deact.'"';
        $html .= ' checked="checked"' if (grep {$_ eq $s} split /,/x,ReadingsVal($name,'devicesDisabled',''));
        $html .= '></label>';
        $html .= '</td>';
        $html .= '<td><a href="/fhem?detail='.$s.'"><strong>'.$s.'</strong>';
        $html .= ' ('.$alias.')' if ($alias);
        $html .= '</a>'.FW_hidden('devname',$s).'</td>';
        $html .= '<td>'.FW_textfieldv('HomeReadingBattery',10,'',AttrVal($s,'HomeReadingBattery',''),AttrVal($name,'HomeSensorsBatteryReading','battery'));
        my $val = ReadingsVal($s,AttrVal($s,'HomeReadingBattery',AttrVal($name,'HomeSensorsBatteryReading','battery')),'');
        $html .= '<span class="dval HOMEMODE_read" informid="'.$name.'-'.$s.'.'.AttrVal($s,'HomeReadingBattery',AttrVal($name,'HomeSensorsBatteryReading','battery')).'">'.(defined $val?$val:'--').'</span>';
        $html .= '<td class="HOMEMODE_tac">';
        my $cl = $val !~ /^\d{1,3}/x?'ui-helper-hidden':'';
        $html .= FW_textfieldv('HomeBatteryLowPercentage',3,$cl,AttrVal($s,'HomeBatteryLowPercentage',''),AttrVal($name,'HomeSensorsBatteryLowPercentage','battery'));
        $html .= '</td>';
        $html .= '</tr>';
        $c++;
      }
      $html .= '</tbody>';
      $html .= '</table>';
    }
    if (@contacts)
    {
      my @hct = ('doorinside','dooroutside','doormain','window');
      my @seasons;
      for (split ' ',AttrVal($name,'HomeSeasons',$HOMEMODE_Seasons))
      {
        push @seasons,(split /\|/x,$_)[1];
      }
      my $sea = join ' ',@seasons;
      $html .= '<table class="block HOMEMODE_table" id="HOMEMODE-Contact-table">';
      $html .= '<thead>';
      $html .= '<tr>';
      $html .= '<th><abbr title="'.$deact.'">#</abbr></th>';
      # $text = $langDE?'Füge neue Kontakte hinzu (kommaseparierte Liste)':'Add new contact sensors (comma separated list)';
      # $html .= '<th>'.$sensor.' <button class="add" title="'.$text.'">+</button></th>';
      $html .= '<th>'.$sensor.'</th>';
      $text = $langDE?
        'Alarm Modus in denen offen als Alarm zu werten ist':
        'Alarm modes to treat open as alarm';
      $html .= '<th><abbr title="'.$text.'">Home<br>ModeAlarmActive</abbr></th>';
      $text = $langDE?
        '1-3 leerzeichenseparierte Werte in Sekunden um den Alarm in den verschiedenen Alarmmodi zu verzögern (armaway armhome armnight)':
        '1-3 space separated values in seconds to delay the alarm for the different alarm modes (armaway armhome armnight)';
      $html .= '<th><abbr title="'.$text.'">Home<br>AlarmDelay</abbr></th>';
      $text = $langDE?
        'Maximale Anzahl wie oft Offen-Warnungen ausgelöst werden sollen':
        'Maximum number how often open warnings should be triggered';
      $html .= '<th><abbr title="'.$text.'">Home<br>OpenMaxTrigger</abbr></th>';
      if (!AttrVal($name,'HomeSensorsContactOpenWarningUnified',0))
      {
        $text = $langDE?
          'Leerzeichen separierte Liste von Minuten nach denen Offen-Warnungen ausgelöst werden sollen':
          'space separated list of minutes after open warning should be triggered';
        $html .= '<th><abbr title="'.$text.'">Home<br>OpenTimes</abbr></th>';
        $text = $langDE?
          'Leerzeichen separierte Liste von Auslösezeit Teilern für Kontaktsensoren Offen-Warnungen abhängig der Jahreszeiten ('.$sea.')':
          'space separated list of trigger time dividers for contact sensor open warnings depending on the seasons ('.$sea.')';
        $html .= '<th><abbr title="'.$text.'">Home<br>OpenTimeDividers</abbr></th>';
      }
      $text = $langDE?
        'Modus von HOMEMODE in welchen Kontaktsensoren keine Offen-Warnungen auslösen sollen':
        'modes of HOMEMODE in which the contact sensor should not trigger open warnings';
      $html .= '<th><abbr title="'.$text.'">Home<br>OpenDontTriggerModes</abbr></th>';
      $text = $langDE?
        'Bewohner deren Status als Referenz für OpenDontTriggerModes gelten soll statt der Modus von HOMEMODE':
        'Residents whose state should be the reference for OpenDontTriggerModes instead of the modes of HOMEMODE';
      $html .= '<th><abbr title="'.$text.'">Home<br>OpenDontTriggerModesResidents</abbr></th>';
      $text = $langDE?
        'Typ des Kontakts':
        'type of the contact sensor';
      $html .= '<th><abbr title="'.$text.'">Home<br>ContactType</abbr></th>';
      $text = $langDE?
        'Name des Reading welches den Kontaktzustand anzeigt':
        'Name of the reading indicating the contact state';
      $html .= '<th><abbr title="'.$text.'">Home<br>ReadingContact</abbr></th>';
      $text = $langDE?
        'Regex von Werten die als offen gewertet werden sollen':
        'Regex of values to be treated as open';
      $html .= '<th><abbr title="'.$text.'">Home<br>ValueContact</abbr></th>';
      $html .= '</tr>';
      $html .= '</thead>';
      $html .= '<tbody>';
      my $c = 1;
      for my $s (sort @contacts)
      {
        my $alias = AttrVal($s,'alias','');
        $html .= '<tr';
        $html .= ' class="';
        $html .= $c%2?'odd':'even';
        $html .= '">';
        $html .= '<td>';
        $html .= '<label><input type="checkbox" name="HomeActive" value="" title="'.$deact.'"';
        $html .= ' checked="checked"' if (grep {$_ eq $s} split /,/x,ReadingsVal($name,'devicesDisabled',''));
        $html .= '></label>';
        $html .= '</td>';
        $html .= '<td><a href="/fhem?detail='.$s.'"><strong>'.$s.'</strong>';
        $html .= ' ('.$alias.')' if ($alias);
        $html .= '</a>'.FW_hidden('devname',$s).'</td>';
        $html .= '<td>';
        $html .= '<label><input type="checkbox" name="HomeModeAlarmActive" value="armaway"';
        $html .= ' checked="checked"' if (grep {$_ eq 'armaway'} split /\|/x,AttrVal($s,'HomeModeAlarmActive',''));
        $html .= '>armaway</label><br>';
        $html .= '<label><input type="checkbox" name="HomeModeAlarmActive" value="armhome"';
        $html .= ' checked="checked"' if (grep {$_ eq 'armhome'} split /\|/x,AttrVal($s,'HomeModeAlarmActive',''));
        $html .= '>armhome</label><br>';
        $html .= '<label><input type="checkbox" name="HomeModeAlarmActive" value="armnight"';
        $html .= ' checked="checked"' if (grep {$_ eq 'armnight'} split /\|/x,AttrVal($s,'HomeModeAlarmActive',''));
        $html .= '>armnight</label>';
        $html .= '</td>';
        $html .= '<td class="HOMEMODE_tac">'.FW_textfieldv('HomeAlarmDelay',3,'',AttrNum($s,'HomeAlarmDelay',undef),AttrNum($name,'HomeSensorsAlarmDelay',0)).'</td>';
        $html .= '<td class="HOMEMODE_tac">'.FW_textfieldv('HomeOpenMaxTrigger',2,'',AttrVal($s,'HomeOpenMaxTrigger',''),0).'</td>';
        if (!AttrVal($name,'HomeSensorsContactOpenWarningUnified',0))
        {
          $html .= '<td class="HOMEMODE_tac">'.FW_textfieldv('HomeOpenTimes',8,'',AttrVal($s,'HomeOpenTimes',''),AttrVal($name,'HomeSensorsContactOpenTimes','10')).'</td>';
          $html .= '<td class="HOMEMODE_tac">'.FW_textfieldv('HomeOpenTimeDividers',7,'',AttrVal($s,'HomeOpenTimeDividers',''),AttrVal($name,'HomeSensorsContactOpenTimeDividers',0)).'</td>';
        }
        $html .= '<td>';
        for my $m (split /,/x,$HOMEMODE_UserModesAll)
        {
          $html .= '<label><input type="checkbox" name="HomeOpenDontTriggerModes" value="'.$m.'"';
          $html .= ' checked="checked"' if (grep {$_ eq $m} split /\|/x,AttrVal($s,'HomeOpenDontTriggerModes',''));
          $html .= '>'.$m.'</label><br>';
        }
        $html .= '</td>';
        $html .= '<td>';
        for my $r (split /,/x,$hash->{RESIDENTS})
        {
          $html .= '<label><input type="checkbox" name="HomeOpenDontTriggerModesResidents" value="'.$r.'"';
          $html .= ' checked="checked"' if (grep {$_ eq $r} split /\|/x,AttrVal($s,'HomeOpenDontTriggerModesResidents',''));
          $html .= '>'.AttrVal($r,'alias',$r).'</label><br>';
        }
        $html .= '</td>';
        $html .= '<td>';
        $html .= FW_select('HomeContactType','HomeContactType',\@hct,AttrVal($s,'HomeContactType',''),'dropdown','');
        $html .= '</td>';
        $html .= '<td>'.FW_textfieldv('HomeReadingContact',10,'',AttrVal($s,'HomeReadingContact',''),AttrVal($name,'HomeSensorsContactReading','state'));
        my $val = ReadingsVal($s,AttrVal($s,'HomeReadingContact',AttrVal($name,'HomeSensorsContactReading','state')),undef);
        $html .= '<span class="dval HOMEMODE_read" informid="'.$name.'-'.$s.'.'.AttrVal($s,'HomeReadingContact',AttrVal($name,'HomeSensorsContactReading','state')).'">'.(defined $val?$val:'--').'</span>';
        $html .= '</td>';
        $html .= '<td class="HOMEMODE_tac">'.FW_textfieldv('HomeValueContact',15,'',AttrVal($s,'HomeValueContact',''),AttrVal($name,'HomeSensorsContactValues','open|tilted|on')).'</td>';
        $html .= '</tr>';
        $c++;
      }
      $html .= '</tbody>';
      $html .= '</table>';
    }
    if (@energies)
    {
      $html .= '<table class="block HOMEMODE_table" id="HOMEMODE-Energy-table">';
      $html .= '<thead>';
      $html .= '<tr>';
      $html .= '<th><abbr title="'.$deact.'">#</abbr></th>';
      $html .= '<th>'.$sensor.'</th>';
      $text = $langDE?
        'Name des Reading welches den Verbrauchswert anzeigt':
        'Name of the reading indicating the energy value';
      $html .= '<th><abbr title="'.$text.'">Home<br>ReadingEnergy</abbr></th>';
      $text = $langDE?
        'Divident für den Verbrauchswert':
        'Divider for the energy value';
      $html .= '<th><abbr title="'.$text.'">Home<br>DividerEnergy</abbr></th>';
      $text = $langDE?
        'Erlaube negative Verbrauchswerte':
        'Allow negative energy values';
      $html .= '<th><abbr title="'.$text.'">Home<br>AllowNegativeEnergy</abbr></th>';
      $html .= '</tr>';
      $html .= '</thead>';
      $html .= '<tbody>';
      my $c = 1;
      for my $s (sort @energies)
      {
        my $alias = AttrVal($s,'alias','');
        $html .= '<tr';
        $html .= ' class="';
        $html .= $c%2?'odd':'even';
        $html .= '">';
        $html .= '<td>';
        $html .= '<label><input type="checkbox" name="HomeActive" value="" title="'.$deact.'"';
        $html .= ' checked="checked"' if (grep {$_ eq $s} split /,/x,ReadingsVal($name,'devicesDisabled',''));
        $html .= '></label>';
        $html .= '</td>';
        $html .= '<td><a href="/fhem?detail='.$s.'"><strong>'.$s.'</strong>';
        $html .= ' ('.$alias.')' if ($alias);
        $html .= '</a>'.FW_hidden('devname',$s).'</td>';
        $html .= '<td>'.FW_textfieldv('HomeReadingEnergy',10,'',AttrVal($s,'HomeReadingEnergy',''),AttrVal($name,'HomeSensorsEnergyReading','energy'));
        my $val = ReadingsVal($s,AttrVal($s,'HomeReadingEnergy',AttrVal($name,'HomeSensorsEnergyReading','energy')),undef);
        $html .= '<span class="dval HOMEMODE_read" informid="'.$name.'-'.$s.'.'.AttrVal($s,'HomeReadingEnergy',AttrVal($name,'HomeSensorsEnergyReading','energy')).'">'.(defined $val?$val:'--').'</span>';
        $html .= '</td>';
        $html .= '<td class="HOMEMODE_tac">'.FW_textfieldv('HomeDividerEnergy',5,'',AttrNum($s,'HomeDividerEnergy',''),AttrNum($name,'HomeSensorsEnergyDivider',1)).'</td>';
        $html .= '<td class="HOMEMODE_tac">';
        $html .= '<label><input type="checkbox" name="HomeAllowNegativeEnergy" value="" title="activate"';
        $html .= ' checked="checked"' if (AttrVal($s,'HomeAllowNegativeEnergy',0));
        $html .= '></label>';
        $html .= '</td>';
        $html .= '</tr>';
        $c++;
      }
      $html .= '</tbody>';
      $html .= '</table>';
    }
    if (@lights)
    {
      $html .= '<form method="get" action="">';
      $html .= '<table class="block HOMEMODE_table" id="HOMEMODE-Luminance-table">';
      $html .= '<thead>';
      $html .= '<tr>';
      $html .= '<th><abbr title="'.$deact.'">#</abbr></th>';
      $html .= '<th>'.$sensor.'</th>';
      $text = $langDE?
        'Name des Reading welches den Lichtwert anzeigt':
        'Name of the reading indicating the light value';
      $html .= '<th><abbr title="'.$text.'">Home<br>ReadingLuminance</abbr></th>';
      $text = $langDE?
        'Divident für den Lichtwert':
        'Divider for the luminance value';
      $html .= '<th><abbr title="'.$text.'">Home<br>DividerLuminance</abbr></th>';
      $html .= '</tr>';
      $html .= '</thead>';
      $html .= '<tbody>';
      my $c = 1;
      for my $s (sort @motions)
      {
        my $alias = AttrVal($s,'alias','');
        my @hmaa = split /\|/x,AttrVal($s,'HomeModeAlarmActive','');
        $html .= '<tr';
        $html .= ' class="';
        $html .= $c%2?'odd':'even';
        $html .= '">';
        $html .= '<td>';
        $html .= '<label><input type="checkbox" name="HomeActive" value="" title="'.$deact.'"';
        $html .= ' checked="checked"' if (grep {$_ eq $s} split /,/x,ReadingsVal($name,'devicesDisabled',''));
        $html .= '></label>';
        $html .= '</td>';
        $html .= '<td><a href="/fhem?detail='.$s.'"><strong>'.$s.'</strong>';
        $html .= ' ('.$alias.')' if ($alias);
        $html .= '</a>'.FW_hidden('devname',$s).'</td>';
        $html .= '<td>'.FW_textfieldv('HomeReadingLuminance',10,'',AttrVal($s,'HomeReadingLuminance',''),AttrVal($name,'HomeSensorsLuminanceReading','luminance'));
        my $val = ReadingsVal($s,AttrVal($s,'HomeReadingLuminance',AttrVal($name,'HomeSensorsLuminanceReading','luminance')),undef);
        $html .= '<span class="dval HOMEMODE_read" informid="'.$name.'-'.$s.'.'.AttrVal($s,'HomeReadingLuminance',AttrVal($name,'HomeSensorsLuminanceReading','luminance')).'">'.(defined $val?$val:'--').'</span>';
        $html .= '</td>';
        $html .= '<td class="HOMEMODE_tac">'.FW_textfieldv('HomeDividerLuminance',5,'',AttrNum($s,'HomeDividerLuminance',''),AttrNum($name,'HomeSensorsLuminanceDivider',1)).'</td>';
        $html .= '</tr>';
        $c++;
      }
      $html .= '</tbody>';
      $html .= '</table>';
    }
    if (@motions)
    {
      my @hml = ('inside','outside');
      $html .= '<table class="block HOMEMODE_table" id="HOMEMODE-Motion-table">';
      $html .= '<thead>';
      $html .= '<tr>';
      $html .= '<th><abbr title="'.$deact.'">#</abbr></th>';
      $html .= '<th>'.$sensor.'</th>';
      $text = $langDE?
        'Alarmmodi wenn open/motion den Alarm auslösen soll':
        'Alarm modes to trigger open/motion as alarm';
      $html .= '<th><abbr title="'.$text.'">Home<br>ModeAlarmActive</abbr></th>';
      $text = $langDE?
        '1-3 leerzeichenseparierte Werte in Sekunden um den Alarm in den verschiedenen Alarmmodi zu verzögern (armaway armhome armnight)':
        '1-3 space separated values in seconds to delay the alarm for the different alarm modes (armaway armhome armnight)';
      $html .= '<th><abbr title="'.$text.'">Home<br>AlarmDelay</abbr></th>';
      $text = $langDE?
        'Standort des Bewegungsmelders':
        'Location of the motion sensor';
      $html .= '<th><abbr title="'.$text.'">Home<br>SensorLocation</abbr></th>';
      $text = $langDE?
        'Name des Reading welches den Bewegungszustand anzeigt':
        'Name of the reading indicating the motion state';
      $html .= '<th><abbr title="'.$text.'">Home<br>ReadingMotion</abbr></th>';
      $text = $langDE?
        'Regex der Werte die als open/motion gewertet werden sollen':
        'Regex of values of ReadingMotion to treat as open/motion';
      $html .= '<th><abbr title="'.$text.'">Home<br>ValueMotion</abbr></th>';
      $html .= '</tr>';
      $html .= '</thead>';
      $html .= '<tbody>';
      my $c = 1;
      for my $s (sort @motions)
      {
        my $alias = AttrVal($s,'alias','');
        my @hmaa = split /\|/x,AttrVal($s,'HomeModeAlarmActive','');
        $html .= '<tr';
        $html .= ' class="';
        $html .= $c%2?'odd':'even';
        $html .= '">';
        $html .= '<td>';
        $html .= '<label><input type="checkbox" name="HomeActive" value="" title="'.$deact.'"';
        $html .= ' checked="checked"' if (grep {$_ eq $s} split /,/x,ReadingsVal($name,'devicesDisabled',''));
        $html .= '></label>';
        $html .= '</td>';
        $html .= '<td><a href="/fhem?detail='.$s.'"><strong>'.$s.'</strong>';
        $html .= ' ('.$alias.')' if ($alias);
        $html .= '</a>'.FW_hidden('devname',$s).'</td>';
        $html .= '<td>';
        $html .= '<label><input type="checkbox" name="HomeModeAlarmActive" value="armaway"';
        $html .= ' checked="checked"' if (grep {$_ eq 'armaway'} @hmaa);
        $html .= '>armaway</label><br>';
        $html .= '<label><input type="checkbox" name="HomeModeAlarmActive" value="armhome"';
        $html .= ' checked="checked"' if (grep {$_ eq 'armhome'} @hmaa);
        $html .= '>armhome</label><br>';
        $html .= '<label><input type="checkbox" name="HomeModeAlarmActive" value="armnight"';
        $html .= ' checked="checked"' if (grep {$_ eq 'armnight'} @hmaa);
        $html .= '>armnight</label>';
        $html .= '</td>';
        $html .= '<td class="HOMEMODE_tac">'.FW_textfieldv('HomeAlarmDelay',3,'',AttrVal($s,'HomeAlarmDelay',''),AttrNum($name,'HomeSensorsAlarmDelay',0)).'</td>';
        $html .= '<td class="HOMEMODE_tac">'.FW_select("$s",'HomeSensorLocation',\@hml,AttrVal($s,'HomeSensorLocation',''),'dropdown','').'</td>';
        $html .= '<td>'.FW_textfieldv('HomeReadingMotion',10,'',AttrVal($s,'HomeReadingMotion',''),AttrVal($name,'HomeSensorsMotionReading','state'));
        my $val = ReadingsVal($s,AttrVal($s,'HomeReadingMotion',AttrVal($name,'HomeSensorsMotionReading','state')),undef);
        $html .= '<span class="dval HOMEMODE_read" informid="'.$name.'-'.$s.'.'.AttrVal($s,'HomeReadingMotion',AttrVal($name,'HomeSensorsMotionReading','state')).'">'.(defined $val?$val:'--').'</span>';
        $html .= '</td>';
        $html .= '<td class="HOMEMODE_tac">'.FW_textfieldv('HomeValueMotion',15,'',AttrVal($s,'HomeValueMotion',''),AttrVal($name,'HomeSensorsMotionValues','motion|open|on|1|true')).'</td>';
        $html .= '</tr>';
        $c++;
      }
      $html .= '</tbody>';
      $html .= '</table>';
    }
    if (@powers)
    {
      $html .= '<table class="block HOMEMODE_table" id="HOMEMODE-Power-table">';
      $html .= '<thead>';
      $html .= '<tr>';
      $html .= '<th><abbr title="'.$deact.'">#</abbr></th>';
      $html .= '<th>'.$sensor.'</th>';
      $text = $langDE?
        'Name des Reading welches den Leistungswert anzeigt':
        'Name of the reading indicating the power value';
      $html .= '<th><abbr title="'.$text.'">Home<br>ReadingPower</abbr></th>';
      $text = $langDE?
        'Divident für den Leistungswert':
        'Divider for the power value';
      $html .= '<th><abbr title="'.$text.'">Home<br>DividerPower</abbr></th>';
      $text = $langDE?
        'Erlaube negative Leistungswerte':
        'Allow negative power values';
      $html .= '<th><abbr title="'.$text.'">Home<br>AllowNegativePower</abbr></th>';
      $html .= '</tr>';
      $html .= '</thead>';
      $html .= '<tbody>';
      my $c = 1;
      for my $s (sort @powers)
      {
        my $alias = AttrVal($s,'alias','');
        $html .= '<tr';
        $html .= ' class="';
        $html .= $c%2?'odd':'even';
        $html .= '">';
        $html .= '<td>';
        $html .= '<label><input type="checkbox" name="HomeActive" value="" title="'.$deact.'"';
        $html .= ' checked="checked"' if (grep {$_ eq $s} split /,/x,ReadingsVal($name,'devicesDisabled',''));
        $html .= '></label>';
        $html .= '</td>';
        $html .= '<td><a href="/fhem?detail='.$s.'"><strong>'.$s.'</strong>';
        $html .= ' ('.$alias.')' if ($alias);
        $html .= '</a>'.FW_hidden('devname',$s).'</td>';
        $html .= '<td>'.FW_textfieldv('HomeReadingPower',10,'',AttrVal($s,'HomeReadingPower',''),AttrVal($name,'HomeSensorsPowerReading','power'));
        my $val = ReadingsVal($s,AttrVal($s,'HomeReadingPower',AttrVal($name,'HomeSensorsPowerReading','power')),undef);
        $html .= '<span class="dval HOMEMODE_read" informid="'.$name.'-'.$s.'.'.AttrVal($s,'HomeReadingPower',AttrVal($name,'HomeSensorsPowerReading','power')).'">'.(defined $val?$val:'--').'</span>';
        $html .= '</td>';
        $html .= '<td class="HOMEMODE_tac">'.FW_textfieldv('HomeDividerPower',5,'',AttrNum($s,'HomeDividerPower',''),AttrNum($name,'HomeSensorsPowerDivider',1)).'</td>';
        $html .= '</td>';
        $html .= '<td class="HOMEMODE_tac">';
        $html .= '<label><input type="checkbox" name="HomeAllowNegativePower" value="" title="activate"';
        $html .= ' checked="checked"' if (AttrVal($s,'HomeAllowNegativePower',0));
        $html .= '></label>';
        $html .= '</td>';
        $html .= '</tr>';
        $c++;
      }
      $html .= '</tbody>';
      $html .= '</table>';
    }
    if (@smokes)
    {
      $html .= '<table class="block HOMEMODE_table" id="HOMEMODE-Smoke-table">';
      $html .= '<thead>';
      $html .= '<tr>';
      $html .= '<th><abbr title="'.$deact.'">#</abbr></th>';
      $html .= '<th>'.$sensor.'</th>';
      $text = $langDE?
        'Name des Reading welches den Rauchmelderstatus anzeigt':
        'Name of the reading indicating the smoke state';
      $html .= '<th><abbr title="'.$text.'">Home<br>ReadingSmoke</abbr></th>';
      $text = $langDE?
        'Regex von Werten des ReadingSmoke die als Rauchalarm gelten sollen':
        'Regex of values of ReadingSmoke to treat as smoke alarm';
      $html .= '<th><abbr title="'.$text.'">Home<br>ValueSmoke</abbr></th>';
      $html .= '</tr>';
      $html .= '</thead>';
      $html .= '<tbody>';
      my $c = 1;
      for my $s (sort @smokes)
      {
        my $alias = AttrVal($s,'alias','');
        $html .= '<tr';
        $html .= ' class="';
        $html .= $c%2?'odd':'even';
        $html .= '">';
        $html .= '<td>';
        $html .= '<label><input type="checkbox" name="HomeActive" value="" title="'.$deact.'"';
        $html .= ' checked="checked"' if (grep {$_ eq $s} split /,/x,ReadingsVal($name,'devicesDisabled',''));
        $html .= '></label>';
        $html .= '</td>';
        $html .= '<td><a href="/fhem?detail='.$s.'"><strong>'.$s.'</strong>';
        $html .= ' ('.$alias.')' if ($alias);
        $html .= '</a>'.FW_hidden('devname',$s).'</td>';
        $html .= '<td>'.FW_textfieldv('HomeReadingSmoke',10,'',AttrVal($s,'HomeReadingSmoke',''),AttrVal($name,'HomeSensorsSmokeReading','state'));
        my $val = ReadingsVal($s,AttrVal($s,'HomeReadingSmoke',AttrVal($name,'HomeSensorsSmokeReading','state')),undef);
        $html .= '<span class="dval HOMEMODE_read" informid="'.$name.'-'.$s.'.'.AttrVal($s,'HomeReadingSmoke',AttrVal($name,'HomeSensorsSmokeReading','state')).'">'.(defined $val?$val:'--').'</span>';
        $html .= '</td>';
        $html .= '<td class="HOMEMODE_tac">'.FW_textfieldv('HomeValueSmoke',15,'',AttrVal($s,'HomeValueSmoke',''),AttrVal($name,'HomeSensorsSmokeValues','smoke|open|on|yes|1|true')).'</td>';
        $html .= '</tr>';
        $c++;
      }
      $html .= '</body>';
      $html .= '</table>';
    }
    if (@tampers)
    {
      $html .= '<table class="block HOMEMODE_table" id="HOMEMODE-Tamper-table">';
      $html .= '<thead>';
      $html .= '<tr>';
      $html .= '<th><abbr title="'.$deact.'">#</abbr></th>';
      $html .= '<th>'.$sensor.'</th>';
      $text = $langDE?
        'Name des Reading welches den Sabotagekontaktstatus anzeigt':
        'Name of the reading indicating the tamper state';
      $html .= '<th><abbr title="'.$text.'">Home<br>ReadingTamper</abbr></th>';
      $text = $langDE?
        'Regex von Werten des ReadingTamper die als Sabotagealarm gelten sollen':
        'Regex of values of ReadingTamper to treat as tamper alarm';
      $html .= '<th><abbr title="'.$text.'">Home<br>ValueTamper</abbr></th>';
      $html .= '</tr>';
      $html .= '</thead>';
      $html .= '<tbody>';
      my $c = 1;
      for my $s (sort @tampers)
      {
        my $alias = AttrVal($s,'alias','');
        $html .= '<tr';
        $html .= ' class="';
        $html .= $c%2?'odd':'even';
        $html .= '">';
        $html .= '<td>';
        $html .= '<label><input type="checkbox" name="HomeActive" value="" title="'.$deact.'"';
        $html .= ' checked="checked"' if (grep {$_ eq $s} split /,/x,ReadingsVal($name,'devicesDisabled',''));
        $html .= '></label>';
        $html .= '</td>';
        $html .= '<td><a href="/fhem?detail='.$s.'"><strong>'.$s.'</strong>';
        $html .= ' ('.$alias.')' if ($alias);
        $html .= '</a>'.FW_hidden('devname',$s).'</td>';
        $html .= '<td>'.FW_textfieldv('HomeReadingTamper',10,'',AttrVal($s,'HomeReadingTamper',''),AttrVal($name,'HomeSensorsTamperReading','sabotageError'));
        my $val = ReadingsVal($s,AttrVal($s,'HomeReadingTamper',AttrVal($name,'HomeSensorsTamperReading','sabotageError')),undef);
        $html .= '<span class="dval HOMEMODE_read" informid="'.$name.'-'.$s.'.'.AttrVal($s,'HomeReadingTamper',AttrVal($name,'HomeSensorsTamperReading','sabotageError')).'">'.(defined $val?$val:'--').'</span>';
        $html .= '</td>';
        $html .= '<td class="HOMEMODE_tac">'.FW_textfieldv('HomeValueTamper',15,'',AttrVal($s,'HomeValueTamper',''),AttrVal($name,'HomeSensorsTamperValues','tamper|open|on|yes|1|true')).'</td>';
        $html .= '</tr>';
        $c++;
      }
      $html .= '</tbody>';
      $html .= '</table>';
    }
    if (@waters)
    {
      $html .= '<table class="block HOMEMODE_table" id="HOMEMODE-Water-table">';
      $html .= '<thead>';
      $html .= '<tr>';
      $html .= '<th><abbr title="'.$deact.'">#</abbr></th>';
      $html .= '<th>'.$sensor.'</th>';
      $text = $langDE?
        'Name des Reading welches den Wassermelderstatus anzeigt':
        'Name of the reading indicating the water state';
      $html .= '<th><abbr title="'.$text.'">Home<br>ReadingWater</abbr></th>';
      $text = $langDE?
        'Regex von Werten des ReadingWater die als Wasseralarm gelten sollen':
        'Regex of values of ReadingWater to treat as water alarm';
      $html .= '<th><abbr title="'.$text.'">Home<br>ValueWater</abbr></th>';
      $html .= '</tr>';
      $html .= '</thead>';
      $html .= '<tbody>';
      my $c = 1;
      for my $s (sort @waters)
      {
        my $alias = AttrVal($s,'alias','');
        $html .= '<tr';
        $html .= ' class="';
        $html .= $c%2?'odd':'even';
        $html .= '">';
        $html .= '<td>';
        $html .= '<label><input type="checkbox" name="HomeActive" value="" title="'.$deact.'"';
        $html .= ' checked="checked"' if (grep {$_ eq $s} split /,/x,ReadingsVal($name,'devicesDisabled',''));
        $html .= '></label>';
        $html .= '</td>';
        $html .= '<td><a href="/fhem?detail='.$s.'"><strong>'.$s.'</strong>';
        $html .= ' ('.$alias.')' if ($alias);
        $html .= '</a>'.FW_hidden('devname',$s).'</td>';
        $html .= '<td>'.FW_textfieldv('HomeReadingWater',10,'',AttrVal($s,'HomeReadingWater',''),AttrVal($name,'HomeSensorsWaterReading','state'));
        my $val = ReadingsVal($s,AttrVal($s,'HomeReadingWater',AttrVal($name,'HomeSensorsWaterReading','state')),undef);
        $html .= '<span class="dval HOMEMODE_read" informid="'.$name.'-'.$s.'.'.AttrVal($s,'HomeReadingWater',AttrVal($name,'HomeSensorsWaterReading','state')).'">'.(defined $val?$val:'--').'</span>';
        $html .= '</td>';
        $html .= '<td class="HOMEMODE_tac">'.FW_textfieldv('HomeValueWater',15,'',AttrVal($s,'HomeValueWater',''),AttrVal($name,'HomeSensorsWaterValues','water|open|on|yes|1|true')).'</td>';
        $html .= '</tr>';
        $c++;
      }
      $html .= '</tbody>';
      $html .= '</table>';
    }
    $html .= '</form>';
    $html .= '</td>';
    $html .= '</tr>';
    $html .= '<tr>';
    $html .= '<td id="HOMEMODE_showInternals">';
    $text = $langDE?'Verstecke Internals und Readings':'hide internals and readings';
    $html .= '<button class="HOMEMODE_internals">'.$text.'</button>';
    $html .= '</td>';
    $html .= '</tr>';
  }
  else
  {
    delete $hash->{helper}{inDetails};
  }
  $html .= '</tbody>';
  $html .= '</table>';
  return $html;
}

sub inform
{
  my ($hash,$item,$value) = @_;
  my $name = $hash->{NAME};
  if ($hash->{helper}{inDetails})
  {
    DoTrigger($name,"$item: $value");
  }
  return;
}

1;

=pod
=item helper
=item summary    home device with ROOMMATE/GUEST/PET integration and much more
=item summary_DE Zuhause Ger&auml;t mit ROOMMATE/GUEST/PET Integration und Vielem mehr
=begin html

<a id="HOMEMODE"></a>
<h3>HOMEMODE</h3>
<ul>
  <i>HOMEMODE</i> is designed to represent the overall home state(s) in one device.<br>
  It uses the attribute userattr extensively.<br>
  It has been optimized for usage with homebridge as GUI.<br>
  You can also configure CMDs to be executed on specific events.<br>
  There is no need to create notify(s) or DOIF(s) to achieve common tasks depending on the home state(s).<br>
  It's also possible to control ROOMMATE/GUEST/PET devices states depending on their associated presence device.<br>
  If the RESIDENTS device is on state home, the HOMEMODE device can automatically change its mode depending on the local time (morning,day,afternoon,evening,night)<br>
  There is also a daytime reading and associated HomeCMD attributes that will execute the HOMEMODE state CMDs independend of the presence of any RESIDENT.<br>
  A lot of placeholders are available for usage within the HomeCMD or HomeText attributes (see Placeholders).<br>
  All your energy and power measuring sensors can be added and calculated total readings for energy and power will be created.<br>
  You can also add your local outside temperature and humidity sensors and you'll get ice warning e.g.<br>
  If you also add your Weather device you'll also get short and long weather informations and weather forecast.<br>
  You can monitor added contact and motion sensors and execute CMDs depending on their state.<br>
  A simple alarm system is included, so your contact and motion sensors can trigger alarms depending on the current alarm mode.<br>
  A lot of customizations are possible, e.g. special events calendars and locations.<br>
  <p><b>General information:</b></p>
  <ul>
    <li>
      The HOMEMODE device is refreshing itselfs every 5 seconds by calling GetUpdate and subfunctions.<br>
      This is the reason why some automations (e.g. daytime or season) are delayed up to 4 seconds.<br>
      All automations triggered by external events (other devices monitored by HOMEMODE) and the execution of the HomeCMD attributes will not be delayed.
    </li>
    <li>
      Each created timer will be created as at device and its name will start with 'atTmp_' and end with '_&lt;name of your HOMEMODE device&gt;'. You may list them with 'list TYPE=at:FILTER=NAME=atTmp_.*_&lt;name of your HOMEMODE device&gt;'.
    </li>
    <li>
      Seasons can also be adjusted (date and text) in attribute HomeSeasons
    </li>
    <li>
      There's a special function, which you may use, which is converting given minutes (up to 5999.99) to a timestamp that can be used for creating at devices.<br>
      This function is called HOMEMODE::hourMaker and the only value you need to pass is the number in minutes with max. two decimal places.
    </li>
    <li>
      Each set command and each updated reading of the HOMEMODE device will create an event within FHEM, so you're able to create additional notify or DOIF devices if needed.
    </li>
  </ul>
  <br>
  <p>A german Wiki page is also available at <a href='https://wiki.fhem.de/wiki/Modul_HOMEMODE' target='_blank'>https://wiki.fhem.de/wiki/Modul_HOMEMODE</a>. There you can find lots of example code.</p>
  <br>
  <a id='HOMEMODE-define'></a>
  <p><b>define [optional]</b></p>
  <ul>
    <code>define &lt;name&gt; HOMEMODE</code><br><br>
    <code>define &lt;name&gt; HOMEMODE [RESIDENTS-MASTER-DEVICE]</code><br>
  </ul>
  <br>
  <a id='HOMEMODE-set'></a>
  <p><b>set &lt;required&gt; [optional]</b></p>
  <ul>
    <li>
      <a id='HOMEMODE-set-anyoneElseAtHome'>anyoneElseAtHome &lt;on/off&gt; [NAME]</a><br>
      turn this on if anyone else is alone at home who is not a registered resident<br>
      e.g. an animal or unregistered guest<br>
      If turned on the alarm mode will be set to armhome instead of armaway while leaving, if turned on after leaving the alarm mode will change from armaway to armhome, e.g. to disable motion sensors alerts.<br>
      If you add a subsequent unique name to the on command, the name will be added to a comma separated list in the reading anyoneElseAtHomeBy.<br>
      If you add a subsequent unique name to the off command, the name will be removed from that list.<br>
      When adding the first name anyoneElseAtHome will be set to on and it will be set to off after removing the last name from that list.<br>
      This is really helpful if you need anyoneElseAtHome mode for more than one use case, e.g. dog at home and a working vacuum cleaner robot.<br>
      placeholder %AEAH% is available in all HomeCMD attributes
    </li>
    <li>
      <a id='HOMEMODE-set-deviceDisable'>deviceDisable &lt;DEVICE&gt;</a><br>
      disable HOMEMODE integration for given device<br>
      placeholder %DISABLED% is available in all HomeCMD attributes<br>
      placeholders %DEVICE% and %ALIAS% are available in HomeCMDdeviceDisable attribute
    </li>
    <li>
      <a id='HOMEMODE-set-deviceEnable'>deviceEnable &lt;DEVICE&gt;</a><br>
      enable HOMEMODE integration for given device<br>
      placeholder %DISABLED% is available in all HomeCMD attributes<br>
      placeholders %DEVICE% and %ALIAS% are available in HomeCMDdeviceEnable attribute
    </li>
    <li>
      <a id='HOMEMODE-set-dnd'>dnd &lt;on/off&gt;</a><br>
      turn 'do not disturb' mode on or off<br>
      e.g. to disable notification or alarms or, or, or...<br>
      placeholder %DND% is available in all HomeCMD attributes
    </li>
    <li>
      <a id='HOMEMODE-set-dnd-for-minutes'>dnd-for-minutes &lt;MINUTES&gt;</a><br>
      turn 'do not disturb' mode on for given minutes<br>
      will return to the current (daytime) mode
    </li>
    <li>
      <a id='HOMEMODE-set-location'>location &lt;arrival/home/bed/underway/wayhome&gt;</a><br>
      switch to given location manually<br>
      placeholder %LOCATION% is available in all HomeCMD attributes
    </li>
    <li>
      <a id='HOMEMODE-set-mode'>mode &lt;morning/day/afternoon/evening/night/gotosleep/asleep/absent/gone/home&gt;</a><br>
      switch to given mode manually<br>
      placeholder %MODE% is available in all HomeCMD attributes
    </li>
    <li>
      <a id='HOMEMODE-set-modeAlarm'>modeAlarm &lt;armaway/armhome/armnight/confirm/disarm&gt;</a><br>
      switch to given alarm mode manually<br>
      placeholder %MODEALARM% is available in all HomeCMD attributes
    </li>
    <li>
      <a id='HOMEMODE-set-modeAlarm-for-minutes'>modeAlarm-for-minutes &lt;armaway/armhome/armnight/disarm&gt; &lt;MINUTES&gt;</a><br>
      switch to given alarm mode for given minutes<br>
      will return to the previous alarm mode
    </li>
    <li>
      <a id='HOMEMODE-set-panic'>panic &lt;on/off&gt;</a><br>
      turn panic mode on or off<br>
      placeholder %PANIC% is available in all HomeCMD attributes
    </li>
    <li>
      <a id='HOMEMODE-set-updateHomebridgeMapping'>updateHomebridgeMapping</a><br>
      will update the attribute homebridgeMapping of the HOMEMODE device depending on the available informations
    </li>
    <li>
      <a id='HOMEMODE-set-updateInternalsForce'>updateInternalsForce</a><br>
      will force update all internals of the HOMEMODE device<br>
      use this if you just reload this module after an update or if you made changes on any HOMEMODE monitored device, e.g. after adding residents/guest or after adding new sensors with the same devspec as before
    </li>
    <li>
      <a id='HOMEMODE-set-updateSensorsUserattr'>updateSensorsUserattr</a><br>
      will force readding of all userattr to all sensors<br>
      use this if you just want to cleanup the userattr on all sensors and readd the nessessary HOMEMODE attributes
    </li>
  </ul>
  <br>
  <a id='HOMEMODE-get'></a>
  <p><b>get &lt;required&gt; [optional]</b></p>
  <ul>
    <li>
      <a id='HOMEMODE-get-contactsOpen'>contactsOpen &lt;all/doorsinside/doorsoutside/doorsmain/outside/windows&gt;</a><br>
      get a list of all/doorsinside/doorsoutside/doorsmain/outside/windows open contacts<br>
      placeholders %OPEN% (open contacts outside) and %OPENCT% (open contacts outside count) are available in all HomeCMD attributes
    </li>
    <li>
      <a id='HOMEMODE-get-devicesDisabled'>devicesDisabled</a><br>
      get new line separated list of currently disabled devices<br>
      placeholder %DISABLED% is available in all HomeCMD attributes
    </li>
    <li>
      <a id='HOMEMODE-get-mode'>mode</a><br>
      get current mode<br>
      placeholder %MODE% is available in all HomeCMD attributes
    </li>
    <li>
      <a id='HOMEMODE-get-modeAlarm'>modeAlarm</a><br>
      get current modeAlarm<br>
      placeholder %MODEALARM% is available in all HomeCMD attributes
    </li>
    <li>
      <a id='HOMEMODE-get-publicIP'>publicIP</a><br>
      get the public IP address<br>
      placeholder %IP% is available in all HomeCMD attributes
    </li>
    <li>
      <a id='HOMEMODE-get-sensorsTampered'>sensorsTampered</a><br>
      get a list of all tampered sensors<br>
      placeholder %TAMPERED% is available in all HomeCMD attributes
    </li>
    <li>
      <a id='HOMEMODE-get-weather'>weather &lt;long/short&gt;</a><br>
      get weather information in given format<br>
      please specify the outputs in attributes HomeTextWeatherLong and HomeTextWeatherShort<br>
      placeholders %WEATHER% and %WEATHERLONG% are available in all HomeCMD attributes
    </li>
    <li>
      <a id='HOMEMODE-get-weatherForecast'>weatherForecast [DAY]</a><br>
      get weather forecast for given day<br>
      if DAY is omitted the forecast for tomorrow (2) will be returned<br>
      please specify the outputs in attributes HomeTextWeatherForecastToday, HomeTextWeatherForecastTomorrow and HomeTextWeatherForecastInSpecDays<br>
      placeholders %FORECAST% (tomorrow) and %FORECASTTODAY% (today) are available in all HomeCMD attributes
    </li>
  </ul>
  <br>
  <a id='HOMEMODE-attr'></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <a id='HOMEMODE-attr-HomeAdvancedDetails'>HomeAdvancedDetails</a><br>
      show more details depending on the monitored devices<br>
      value detail will only show advanced details in detail view, value both will show advanced details also in room view, room will show advanced details only in room view<br>
      values: none, detail, both, room<br>
      default: none
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeAdvancedAttributes'>HomeAdvancedAttributes</a><br>
      more HomeCMD attributes will be provided<br>
      additional attributes for each resident and each calendar event<br>
      values: 0 or 1<br>
      default: 0
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeAtTmpRoom'>HomeAtTmpRoom</a><br>
      add this room to temporary at(s) (generated by HOMEMODE)<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeAutoAlarmModes'>HomeAutoAlarmModes</a><br>
      set modeAlarm automatically depending on mode<br>
      if mode is set to 'home', modeAlarm will be set to 'disarm'<br>
      if mode is set to 'absent', modeAlarm will be set to 'armaway'<br>
      if mode is set to 'asleep', modeAlarm will be set to 'armnight'<br>
      modeAlarm 'home' can only be set manually<br>
      values 0 or 1, value 0 disables automatically set modeAlarm<br>
      default: 1
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeAutoArrival'>HomeAutoArrival</a><br>
      set resident's location to arrival (on arrival) and after given minutes to home<br>
      values from 0 to 5999.9 in minutes, value 0 disables automatically set arrival<br>
      default: 0
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeAutoAsleep'>HomeAutoAsleep</a><br>
      set user from gotosleep to asleep after given minutes<br>
      values from 0 to 5999.9 in minutes, value 0 disables automatically set asleep<br>
      default: 0
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeAutoAwoken'>HomeAutoAwoken</a><br>
      force set resident from asleep to awoken, even if changing from alseep to home<br>
      after given minutes awoken will change to home<br>
      values from 0 to 5999.9 in minutes, value 0 disables automatically set awoken after asleep<br>
      default: 0
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeAutoDaytime'>HomeAutoDaytime</a><br>
      daytime depending home mode<br>
      values 0 or 1, value 0 disables automatically set daytime<br>
      default: 1
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeAutoPresence'>HomeAutoPresence</a><br>
      automatically change the state of residents between home and absent depending on their associated presence device<br>
      values 0 or 1, value 0 disables auto presence<br>
      default: 0
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeAutoPresenceSuppressState'>HomeAutoPresenceSuppressState</a><br>
      suppress state(s) for HomeAutoPresence (p.e. gotosleep|asleep)<br>
      if set this/these state(s) of a resident will not affect the residents to change to absent by its presence device<br>
      p.e. for misteriously disappearing presence devices in the middle of the night<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDalarmSmoke'>HomeCMDalarmSmoke</a><br>
      cmds to execute on any smoke alarm state
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDalarmSmoke-' data-pattern='HomeCMDalarmSmoke-.*'>HomeCMDalarmSmoke-&lt;on/off&gt;</a><br>
      cmds to execute on smoke alarm state on/off
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDalarmTampered'>HomeCMDalarmTampered</a><br>
      cmds to execute on any tamper alarm state
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDalarmTampered-' data-pattern='HomeCMDalarmTampered-.*'>HomeCMDalarmTampered-&lt;on/off&gt;</a><br>
      cmds to execute on tamper alarm state on/off
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDalarmTriggered'>HomeCMDalarmTriggered</a><br>
      cmds to execute on any alarm state
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDalarmTriggered-' data-pattern='HomeCMDalarmTriggered-.*'>HomeCMDalarmTriggered-&lt;on/off&gt;</a><br>
      cmds to execute on alarm state on/off
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDalarmWater'>HomeCMDalarmWater</a><br>
      cmds to execute on any water alarm state
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDalarmWater-' data-pattern='HomeCMDalarmWater-.*'>HomeCMDalarmWater-&lt;on/off&gt;</a><br>
      cmds to execute on water alarm state on/off
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDanyoneElseAtHome'>HomeCMDanyoneElseAtHome</a><br>
      cmds to execute on any anyoneElseAtHome state
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDanyoneElseAtHome-' data-pattern='HomeCMDanyoneElseAtHome-.*'>HomeCMDanyoneElseAtHome-&lt;on/off&gt;</a><br>
      cmds to execute on anyoneElseAtHome state on/off
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDcontact'>HomeCMDcontact</a><br>
      cmds to execute if any contact has been triggered (open/tilted/closed)
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDbattery'>HomeCMDbattery</a><br>
      cmds to execute on any battery change of a battery sensor
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDbatteryLow'>HomeCMDbatteryLow</a><br>
      cmds to execute if any battery sensor has low battery
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDbatteryNormal'>HomeCMDbatteryNormal</a><br>
      cmds to execute if any battery sensor returns to normal battery
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDcontactClosed'>HomeCMDcontactClosed</a><br>
      cmds to execute if any contact has been closed
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDcontactOpen'>HomeCMDcontactOpen</a><br>
      cmds to execute if any contact has been opened
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDcontactDoormain'>HomeCMDcontactDoormain</a><br>
      cmds to execute if any contact of type doormain has been triggered (open/tilted/closed)
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDcontactDoormainClosed'>HomeCMDcontactDoormainClosed</a><br>
      cmds to execute if any contact of type doormain has been closed
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDcontactDoormainOpen'>HomeCMDcontactDoormainOpen</a><br>
      cmds to execute if any contact of type doormain has been opened
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDcontactOpenWarning1'>HomeCMDcontactOpenWarning1</a><br>
      cmds to execute on first contact open warning
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDcontactOpenWarning2'>HomeCMDcontactOpenWarning2</a><br>
      cmds to execute on second (and more) contact open warning
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDcontactOpenWarningLast'>HomeCMDcontactOpenWarningLast</a><br>
      cmds to execute on last contact open warning
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDdaytime'>HomeCMDdaytime</a><br>
      cmds to execute on any daytime change
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDdaytime-' data-pattern='HomeCMDdaytime-.*'>HomeCMDdaytime-&lt;%DAYTIME%&gt;</a><br>
      cmds to execute on specific day time change
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDdeviceDisable'>HomeCMDdeviceDisable</a><br>
      cmds to execute on set HOMEMODE deviceDisable
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDdeviceEnable'>HomeCMDdeviceEnable</a><br>
      cmds to execute on set HOMEMODE deviceEnable
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDdnd'>HomeCMDdnd</a><br>
      cmds to execute on any dnd state
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDdnd-' data-pattern='HomeCMDdnd-.*'>HomeCMDdnd-&lt;on/off&gt;</a><br>
      cmds to execute on dnd state on/off
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDevent'>HomeCMDevent</a><br>
      cmds to execute on each calendar event
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDevent-' data-pattern='HomeCMDevent-.*-each'>HomeCMDevent-&lt;%CALENDAR%&gt;-each</a><br>
      cmds to execute on each event of the calendar
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDevent-' data-pattern='HomeCMDevent-.*-.*-begin'>HomeCMDevent-&lt;%CALENDAR%&gt;-&lt;%EVENT%&gt;-begin</a><br>
      cmds to execute on start of a specific calendar event
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDevent-' data-pattern='HomeCMDevent-.*-.*-end'>HomeCMDevent-&lt;%CALENDAR%&gt;-&lt;%EVENT%&gt;-end</a><br>
      cmds to execute on end of a specific calendar event
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDfhemDEFINED'>HomeCMDfhemDEFINED</a><br>
      cmds to execute on any defined device
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDfhemINITIALIZED'>HomeCMDfhemINITIALIZED</a><br>
      cmds to execute on fhem start
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDfhemSAVE'>HomeCMDfhemSAVE</a><br>
      cmds to execute on fhem save
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDfhemUPDATE'>HomeCMDfhemUPDATE</a><br>
      cmds to execute on fhem update
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDicewarning'>HomeCMDicewarning</a><br>
      cmds to execute on any ice warning state
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDicewarning-' data-pattern='HomeCMDicewarning-.*'>HomeCMDicewarning-&lt;on/off&gt;</a><br>
      cmds to execute on ice warning state on/off
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDlocation'>HomeCMDlocation</a><br>
      cmds to execute on any location change of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDlocation-' data-pattern='HomeCMDlocation-.*'>HomeCMDlocation-&lt;%LOCATION%&gt;</a><br>
      cmds to execute on specific location change of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDlocation-resident'>HomeCMDlocation-resident</a><br>
      cmds to execute on any location change of any RESIDENT/GUEST/PET device
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDlocation-' data-pattern='HomeCMDlocation-.*-.*'>HomeCMDlocation-&lt;%LOCATIONR%&gt;-&lt;%RESIDENT%&gt;</a><br>
      cmds to execute on specific location change of a specific RESIDENT/GUEST/PET device
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDlocation-' data-pattern='HomeCMDlocation-.*-resident'>HomeCMDlocation-&lt;%LOCATIONR%&gt;-resident</a><br>
      cmds to execute on specific location change of any RESIDENT/GUEST/PET device
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDmode'>HomeCMDmode</a><br>
      cmds to execute on any mode change of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDmode-absent-belated'>HomeCMDmode-absent-belated</a><br>
      cmds to execute belated to absent<br>
      belated time can be adjusted with attribute 'HomeModeAbsentBelatedTime'
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDmode-' data-pattern='HomeCMDmode-.*'>HomeCMDmode-&lt;%MODE%&gt;</a><br>
      cmds to execute on specific mode change of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDmode-' data-pattern='HomeCMDmode-.*-.*'>HomeCMDmode-&lt;%MODE%&gt;-&lt;%RESIDENT%&gt;</a><br>
      cmds to execute on specific mode change of the HOMEMODE device triggered by a specific resident
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDmode-' data-pattern='HomeCMDmode-.*-resident'>HomeCMDmode-&lt;%MODE%&gt;-resident</a><br>
      cmds to execute on specific mode change of the HOMEMODE device triggered by any resident
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDmodeAlarm'>HomeCMDmodeAlarm</a><br>
      cmds to execute on any alarm mode change
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDmodeAlarm-' data-pattern='HomeCMDmodeAlarm-.*'>HomeCMDmodeAlarm-&lt;armaway/armhome/armnight/confirm/disarm&gt;</a><br>
      cmds to execute on specific alarm mode change
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDmotion'>HomeCMDmotion</a><br>
      cmds to execute on any recognized motion of any motion sensor
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDmotion-' data-pattern='HomeCMDmotion-.*'>HomeCMDmotion-&lt;on/off&gt;</a><br>
      cmds to execute if any recognized motion of any motion sensor ends/starts
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDpanic'>HomeCMDpanic</a><br>
      cmds to execute on any panic state
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDpanic-' data-pattern='HomeCMDpanic-.*'>HomeCMDpanic-&lt;on/off&gt;</a><br>
      cmds to execute on if panic is turned on/off
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDpresence-' data-pattern='HomeCMDpresence-(absent|present)'>HomeCMDpresence-&lt;absent/present&gt;</a><br>
      cmds to execute on specific presence change of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDpresence-' data-pattern='HomeCMDpresence-(absent|present)-.+'>HomeCMDpresence-&lt;absent/present&gt;-&lt;%RESIDENT%&gt;</a><br>
      cmds to execute on specific presence change of a specific resident
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDpresence-' data-pattern='HomeCMDpresence-(absent|present)-device'>HomeCMDpresence-&lt;absent/present&gt;-device</a><br>
      cmds to execute on specific presence change of any presence device
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDpresence-' data-pattern='HomeCMDpresence-(absent|present)-resident'>HomeCMDpresence-&lt;absent/present&gt;-resident</a><br>
      cmds to execute on specific presence change of a specific resident
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDpresence-' data-pattern='HomeCMDpresence-(absent|present)-.+-.+'>HomeCMDpresence-&lt;absent/present&gt;-&lt;%RESIDENT%&gt;-&lt;%DEVICE%&gt;</a><br>
      cmds to execute on specific presence change of a specific resident's presence device<br>
      only available if more than one presence device is available for a resident
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDpublic-ip-change'>HomeCMDpublic-ip-change</a><br>
      cmds to execute on any detected public IP change
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDseason'>HomeCMDseason</a><br>
      cmds to execute on any season change
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDseason-' data-pattern='HomeCMDseason-.+'>HomeCMDseason-&lt;%SEASON%&gt;</a><br>
      cmds to execute on specific season change
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDtwilight'>HomeCMDtwilight</a><br>
      cmds to execute on any twilight event
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDtwilight-' data-pattern='HomeCMDtwilight-.+'>HomeCMDtwilight-&lt;EVENT&gt;</a><br>
      cmds to execute on a specific twilight event
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDuwz-warn'>HomeCMDuwz-warn</a><br>
      cmds to execute on any UWZ warning state
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeCMDuwz-warn-' data-pattern='HomeCMDuwz-warn-.+'>HomeCMDuwz-warn-&lt;begin/end&gt;</a><br>
      cmds to execute on UWZ warning state begin/end
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeDaytimes'>HomeDaytimes</a><br>
      space separated list of time|text pairs for possible daytimes starting with the first event of the day (lowest time)<br>
      default: 05:00|morning 10:00|day 14:00|afternoon 18:00|evening 23:00|night
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeEventsDevices'>HomeEventsDevices</a><br>
      devspec of Calendar/holiday calendars
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeEventsFilter-' data-pattern='HomeEventsFilter-.*'>HomeEventsFilter-&lt;%CALENDAR%&gt;</a><br>
      regex to get filtered calendar/holiday events<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeIcewarningOnOffTemps'>HomeIcewarningOnOffTemps</a><br>
      2 space separated temperatures for ice warning on and off<br>
      default: 2 3
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeLanguage'>HomeLanguage</a><br>
      overwrite language from gloabl device<br>
      default: EN (language setting from global device)
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeModeAbsentBelatedTime'>HomeModeAbsentBelatedTime</a><br>
      time in minutes after changing to absent to execute 'HomeCMDmode-absent-belated'<br>
      if mode changes back (to home e.g.) in this time frame 'HomeCMDmode-absent-belated' will not be executed<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeModeAlarmArmDelay'>HomeModeAlarmArmDelay</a><br>
      time in seconds for delaying modeAlarm arm... commands<br>
      must be a single number (valid for all modeAlarm arm... commands) or 3 space separated numbers for each modeAlarm arm... command individually (order: armaway armnight armhome)<br>
      values from 0 to 99999<br>
      default: 0
    </li>
    <li>
      <a id='HOMEMODE-attr-HomePresenceDeviceAbsentCount-' data-pattern='HomePresenceDeviceAbsentCount-.+'>HomePresenceDeviceAbsentCount-&lt;ROOMMATE/GUEST/PET&gt;</a><br>
      number of resident associated presence device to turn resident to absent<br>
      default: maximum number of available presence device for each resident
    </li>
    <li>
      <a id='HOMEMODE-attr-HomePresenceDevicePresentCount-' data-pattern='HomePresenceDevicePresentCount-.+'>HomePresenceDevicePresentCount-&lt;ROOMMATE/GUEST/PET&gt;</a><br>
      number of resident associated presence device to turn resident to home<br>
      default: 1
    </li>
    <li>
      <a id='HOMEMODE-attr-HomePresenceDeviceType'>HomePresenceDeviceType</a><br>
      comma separated list of presence device types<br>
      default: PRESENCE
    </li>
    <li>
      <a id='HOMEMODE-attr-HomePublicIpCheckInterval'>HomePublicIpCheckInterval</a><br>
      numbers from 1-99999 for interval in minutes for public IP check<br>
      default: 0 (disabled)
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeResidentCmdDelay'>HomeResidentCmdDelay</a><br>
      time in seconds to delay the execution of specific residents commands after the change of the residents master device<br>
      normally the resident events occur before the HOMEMODE events, to restore this behavior set this value to 0<br>
      default: 1 (second)
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSeasons'>HomeSeasons</a><br>
      space separated list of date|text pairs for possible seasons starting with the first season of the year (lowest date)<br>
      default: 01.01|spring 06.01|summer 09.01|autumn 12.01|winter
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorAirpressure'>HomeSensorAirpressure</a><br>
      main outside airpressure sensor
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorWindspeed'>HomeSensorWindspeed</a><br>
      main outside wind speed sensor
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsAlarmDelay'>HomeSensorsAlarmDelay</a><br>
      number in seconds to delay an alarm triggered by a contact or motion sensor<br>
      this is the global setting, you can also set this in each contact and motion sensor individually in attribute HomeAlarmDelay once they are added to the HOMEMODE device<br>
      default: 0
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsBattery'>HomeSensorsBattery</a><br>
      devspec of battery sensors with a battery reading<br>
      all sensors with a percentage battery value or a ok/low/nok battery value are applicable<br>
      each applied battery sensor will get the following attributes, attributes will be removed after removing the battery sensors from the HOMEMODE device.<br>
      <ul>
        <li>
          <a id='HOMEMODE-attr-HomeReadingBattery'>HomeReadingBattery</a><br>
          Single word of name of the reading indicating the battery value<br>
          this is the device setting which will override the global setting from attribute HomeSensorsBatteryReading of the HOMEMODE device<br>
          default: state
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeBatteryLowPercentage'>HomeBatteryLowPercentage</a><br>
          percentage to recognize a sensors battery as low (only percentage based sensors)<br>
          this is the device setting which will override the global setting from attribute HomeSensorsBatteryLowPercentage of the HOMEMODE device<br>
          default: 1
        </li>
      </ul>
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsBatteryLowPercentage'>HomeSensorsBatteryLowPercentage</a><br>
      percentage to recognize a sensors battery as low (only percentage based sensors)<br>
      default: 30
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsBatteryReading'>HomeSensorsBatteryReading</a><br>
      a single word of name of the reading indicating the battery value<br>
      this is only here available as global setting for all devices<br>
      default: battery
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsContact'>HomeSensorsContact</a><br>
      devspec of contact sensors<br>
      each applied contact sensor will get the following attributes, attributes will be removed after removing the contact sensors from the HOMEMODE device.<br>
      <ul>
        <li>
          <a id='HOMEMODE-attr-HomeContactType'>HomeContactType</a><br>
          specify each contacts sensor's type, choose one of: doorinside, dooroutside, doormain, window<br>
          while applying contact sensors to the HOMEMODE device, the value of this attribute will be guessed by device name or device alias
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeModeAlarmActive'>HomeModeAlarmActive</a><br>
          specify the alarm mode(s) by regex in which the contact sensor should trigger open/tilted as alerts<br>
          while applying contact sensors to the HOMEMODE device, the value of this attribute will be set to armaway by default<br>
          choose one or a combination of: armaway|armhome|armnight<br>
          default: armaway
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeOpenDontTriggerModes'>HomeOpenDontTriggerModes</a><br>
          specify the HOMEMODE mode(s)/state(s) by regex in which the contact sensor should not trigger open warnings<br>
          choose one or a combination of all available modes of the HOMEMODE device<br>
          if you don't want open warnings while sleeping a good choice would be: gotosleep|asleep<br>
          default:
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeOpenDontTriggerModesResidents'>HomeOpenDontTriggerModesResidents</a><br>
          comma separated list of residents whose state should be the reference for HomeOpenDontTriggerModes instead of the mode of the HOMEMODE device<br>
          if one of the listed residents is in the state given by attribute HomeOpenDontTriggerModes, open warnings will not be triggered for this contact sensor<br>
          default:
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeOpenMaxTrigger'>HomeOpenMaxTrigger</a><br>
          maximum number how often open warning should be repeated<br>
          default: 0
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeReadingContact'>HomeReadingContact</a><br>
          single word of name of the reading indicating the contact state<br>
          this is the device setting which will override the global setting from attribute HomeSensorsContactReading of the HOMEMODE device<br>
          default: state
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeValueContact'>HomeValueContact</a><br>
          regex of open and tilted values for contact sensors<br>
          this is the device setting which will override the global setting from attribute HomeSensorsContactValues of the HOMEMODE device<br>
          default: open|tilted|on
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeOpenTimes'>HomeOpenTimes</a><br>
          space separated list of minutes after open warning should be triggered<br>
          first value is for first warning, second value is for second warning, ...<br>
          if less values are available than the number given by HomeOpenMaxTrigger, the very last available list entry will be used<br>
          this is the device setting which will override the global setting from attribute HomeSensorsContactOpenTimes of the HOMEMODE device<br>
          default: 10
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeOpenTimeDividers'>HomeOpenTimeDividers</a><br>
          space separated list of trigger time dividers for contact sensor open warnings depending on the season of the HOMEMODE device.<br>
          dividers in same order and same number as seasons in attribute HomeSeasons<br>
          dividers are not used for contact sensors of type doormain and doorinside!<br>
          this is the device setting which will override the global setting from attribute HomeSensorsContactOpenTimeDividers of the HOMEMODE device<br>
          values from 0.001 to 99.999<br>
          default:
        </li>
      </ul>
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsContactReading'>HomeSensorsContactReading</a><br>
      single word of name of the reading indicating the contact state<br>
      this is the global setting, you can also set these readings in each contact sensor individually in attribute HomeReadingContact once they are added to the HOMEMODE device<br>
      default: state
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsContactValues'>HomeSensorsContactValues</a><br>
      regex of open and tilted values for contact sensors<br>
      this is the global setting, you can also set these values in each contact sensor individually in attribute HomeValueContact once they are added to the HOMEMODE device<br>
      default: open|tilted|on|1|true
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsContactOpenTimeDividers'>HomeSensorsContactOpenTimeDividers</a><br>
      space separated list of trigger time dividers for contact sensor open warnings depending on the season of the HOMEMODE device.<br>
      dividers in same order and same number as seasons in attribute HomeSeasons<br>
      dividers are not used for contact sensors of type doormain and doorinside!<br>
      this is the global setting, you can also set these dividers in each contact sensor individually in attribute HomeOpenTimeDividers once they are added to the HOMEMODE device<br>
      values from 0.001 to 99.999<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsContactOpenTimeMin'>HomeSensorsContactOpenTimeMin</a><br>
      minimal open time for contact sensors open warnings<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsContactOpenTimes'>HomeSensorsContactOpenTimes</a><br>
      space separated list of minutes after open warning should be triggered<br>
      first value is for first warning, second value is for second warning, ...<br>
      if less values are available than the number given by HomeOpenMaxTrigger, the very last available list entry will be used<br>
      this is the global setting, you can also set these times(s) in each contact sensor individually in attribute HomeOpenTimes once they are added to the HOMEMODE device<br>
      default: 10
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsContactOpenWarningUnified'>HomeSensorsContactOpenWarningUnified</a><br>
      if enabled all contact open warnings will be treated as one instead of individual ones<br>
      now only the global values for HomeSensorsContactOpenTimeDividers and HomeSensorsContactOpenTimes are used and the ones on the individual sensors are being removed<br>
      values: 0 or 1<br>
      default: 0
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorHumidityOutside'>HomeSensorHumidityOutside</a><br>
      main outside humidity sensor<br>
      if HomeSensorTemperatureOutside also has a humidity reading, you don't need to add the same sensor here
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorTemperatureOutside'>HomeSensorTemperatureOutside</a><br>
      main outside temperature sensor<br>
      if this sensor also has a humidity reading, you don't need to add the same sensor to HomeSensorHumidityOutside
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsLuminance'>HomeSensorsLuminance</a><br>
      devspec of sensors with luminance measurement capabilities<br>
      these devices will be used for total luminance calculations<br>
      please set the corresponding reading for luminance in attribute HomeSensorsLuminanceReading (if different to luminance) before applying sensors here<br>
      each applied luminance sensor will get the following attributes, attributes will be removed after removing the luminance sensors from the HOMEMODE device.<br>
      <ul>
        <li>
          <a id='HOMEMODE-attr-HomeReadingLuminance'>HomeReadingLuminance</a><br>
          single word of name of the reading indicating the contact state<br>
          this is the device setting which will override the global setting from attribute HomeSensorsLuminanceReading of the HOMEMODE device<br>
          default: state sabotageError
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeDividerLuminance'>HomeDividerLuminance</a><br>
          divider for proper calculation of total luminance<br>
          this is the device setting which will override the global setting from attribute HomeSensorsLuminanceDivider of the HOMEMODE device<br>
          default: 1
        </li>
      </ul>
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsLuminanceReading'>HomeSensorsLuminanceReading</a><br>
      single word of name of the reading indicating the contact state<br>
      this is the global setting, you can also set these values in each contact sensor individually in attribute HomeReadingLuminance once they are added to the HOMEMODE device<br>
      default: luminance
    </li>
      <a id='HOMEMODE-attr-HomeSensorsLuminanceDivider'>HomeSensorsLuminanceDivider</a><br>
      divider for proper calculation of total luminance<br>
      this is the global setting, you can also set these values in each contact sensor individually in attribute HomeDividerLuminance once they are added to the HOMEMODE device<br>
      default: 1
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsMotion'>HomeSensorsMotion</a><br>
      devspec of motion sensors<br>
      each applied motion sensor will get the following attributes, attributes will be removed after removing the motion sensors from the HOMEMODE device.<br>
      <ul>
        <li>
          <a id='HOMEMODE-attr-HomeModeAlarmActive'>HomeModeAlarmActive</a><br>
          specify the alarm mode(s) by regex in which the motion sensor should trigger motions as alerts<br>
          while applying motion sensors to the HOMEMODE device, the value of this attribute will be set to armaway by default<br>
          choose one or a combination of: armaway|armhome|armnight<br>
          default: armaway (if sensor is of type inside)
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeSensorLocation'>HomeSensorLocation</a><br>
          specify each motion sensor's location, choose one of: inside, outside<br>
          default: inside
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeReadingMotion'>HomeReadingMotion</a><br>
          single word of name of the reading indicating the motion state<br>
          this is the device setting which will override the global setting from attribute HomeSensorsMotionReading of the HOMEMODE device<br>
          default: state sabotageError
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeValueMotion'>HomeValueMotion</a><br>
          regex of open values for the motion sensor<br>
          this is the device setting which will override the global setting from attribute HomeSensorsMotionValues of the HOMEMODE device<br>
          default: open|on|motion|1|true
        </li>
      </ul>
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsMotionReading'>HomeSensorsMotionReading</a><br>
      single word of name of the reading indicating the motion state<br>
      this is the global setting, you can also set these in each motion sensor individually in attribute HomeReadingMotion once they are added to the HOMEMODE device<br>
      default: state
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsMotionValues'>HomeSensorsMotionValues</a><br>
      regex of open and tamper values for motion sensors<br>
      this is the global setting, you can also set these values in each contact sensor individually in attribute HomeValueMotion once they are added to the HOMEMODE device<br>
      default: open|on|motion|1|true
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsEnergy'>HomeSensorsEnergy</a><br>
      devspec of sensors with energy reading<br>
      these devices will be used for total energy calculations<br>
      each applied energy sensor will get the following attributes, attributes will be removed after removing the energy sensors from the HOMEMODE device.<br>
      <ul>
        <li>
          <a id='HOMEMODE-attr-HomeAllowNegativeEnergy'>HomeAllowNegativeEnergy</a><br>
          aalow negative energy values for total calculation<br>
          default: 0
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeDividerEnergy'>HomeDividerEnergy</a><br>
          divider for proper calculation of total energy consumption<br>
          this is the device setting which will override the global setting from attribute HomeSensorsEnergyDivider of the HOMEMODE device<br>
          default: 1
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeReadingEnergy'>HomeReadingEnergy</a><br>
          single word of name of the reading indicating the energy value<br>
          this is the device setting which will override the global setting from attribute HomeSensorsEnergyReading of the HOMEMODE device<br>
          default: energy
        </li>
      </ul>
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsEnergyDivider'>HomeSensorsEnergyDivider</a><br>
      divider for proper calculation of total energy consumption<br>
      default: 1
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsEnergyReading'>HomeSensorsEnergyReading</a><br>
      single word of name of the reading indicating the energy value<br>
      default: energy
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsPower'>HomeSensorsPower</a><br>
      devspec of sensors with power reading<br>
      these devices will be used for total calculations<br>
      each applied power sensor will get the following attributes, attributes will be removed after removing the power sensors from the HOMEMODE device.<br>
      <ul>
        <li>
          <a id='HOMEMODE-attr-HomeAllowNegativePower'>HomeAllowNegativePower</a><br>
          allow negative power values for total calculation<br>
          default: 0
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeDividerPower'>HomeDividerPower</a><br>
          divider for proper calculation of total power consumption<br>
          this is the device setting which will override the global setting from attribute HomeSensorsPowerDivider of the HOMEMODE device<br>
          default: 1
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeReadingPower'>HomeReadingPower</a><br>
          single word of name of the reading indicating the power value<br>
          this is the device setting which will override the global setting from attribute HomeSensorsPowerReading of the HOMEMODE device<br>
          default: state sabotageError
        </li>
      </ul>
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsPowerDivider'>HomeSensorsPowerDivider</a><br>
      divider for proper calculation of total power consumption<br>
      this is the global setting, you can also set these values in each contact sensor individually in attribute HomeDividerPower once they are added to the HOMEMODE device<br>
      default: 1
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsPowerReading'>HomeSensorsPowerReading</a><br>
      single word of name of the reading indicating the energy value<br>
      this is the global setting, you can also set these values in each contact sensor individually in attribute HomeReadingPower once they are added to the HOMEMODE device<br>
      default: power
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsSmoke'>HomeSensorsSmoke</a><br>
      devspec of smoke sensors<br>
      <ul>
        <li>
          <a id='HOMEMODE-attr-HomeReadingSmoke'>HomeReadingSmoke</a><br>
          single word of name of the reading indicating the smoke state<br>
          this is the device setting which will override the global setting from attribute HomeSensorsSmokeReading of the HOMEMODE device<br>
          default: state sabotageError
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeValueSmoke'>HomeValueSmoke</a><br>
          regex of on values for the smoke sensor<br>
          this is the device setting which will override the global setting from attribute HomeSensorsSmokeValues of the HOMEMODE device<br>
          default: smoke|open|on|yes|1|true
        </li>
      </ul>
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsSmokeReading'>HomeSensorsSmokeReading</a><br>
      single word of name of the reading indicating the smoke state<br>
      this is the global setting, you can also set these values in each contact sensor individually in attribute HomeReadingSmoke once they are added to the HOMEMODE device<br>
      default: state
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsSmokeValues'>HomeSensorsSmokeValues</a><br>
      regex of on values for smoke sensors<br>
      this is the global setting, you can also set these values in each contact sensor individually in attribute HomeValueSmoke once they are added to the HOMEMODE device<br>
      default: on
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsTamper'>HomeSensorsTamper</a><br>
      devspec of smoke sensors<br>
      <ul>
        <li>
          <a id='HOMEMODE-attr-HomeReadingTamper'>HomeReadingTamper</a><br>
          single word of name of the reading indicating the tamper state<br>
          this is the device setting which will override the global setting from attribute HomeSensorsTamperReading of the HOMEMODE device<br>
          default: state sabotageError
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeValueTamper'>HomeValueTamper</a><br>
          regex of on values for the tamper sensor<br>
          this is the device setting which will override the global setting from attribute HomeSensorsTamperValues of the HOMEMODE device<br>
          default: tamper|open|on|yes|1|true
        </li>
      </ul>
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsTamperReading'>HomeSensorsTamperReading</a><br>
      single word of name of the reading indicating the tamper state<br>
      this is the global setting, you can also set these values in each contact sensor individually in attribute HomeReadingTamper once they are added to the HOMEMODE device<br>
      default: state
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsTamperValues'>HomeSensorsTamperValues</a><br>
      regex of on values for smoke sensors<br>
      this is the global setting, you can also set these values in each contact sensor individually in attribute HomeValueTamper once they are added to the HOMEMODE device<br>
      default: tamper|open|on|yes|1|true
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsWater'>HomeSensorsWater</a><br>
      devspec of smoke sensors<br>
      <ul>
        <li>
          <a id='HOMEMODE-attr-HomeReadingWater'>HomeReadingWater</a><br>
          single word of name of the reading indicating the water state<br>
          this is the device setting which will override the global setting from attribute HomeSensorsWaterReading of the HOMEMODE device<br>
          default: state sabotageError
        </li>
        <li>
          <a id='HOMEMODE-attr-HomeValueWater'>HomeValueWater</a><br>
          regex of on values for the water sensor<br>
          this is the device setting which will override the global setting from attribute HomeSensorsWaterValues of the HOMEMODE device<br>
          default: water|open|on|yes|1|true
        </li>
      </ul>
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsWaterReading'>HomeSensorsWaterReading</a><br>
      single word of name of the reading indicating the water state<br>
      this is the global setting, you can also set these values in each contact sensor individually in attribute HomeReadingWater once they are added to the HOMEMODE device<br>
      default: state
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSensorsWaterValues'>HomeSensorsWaterValues</a><br>
      regex of on values for water sensors<br>
      this is the global setting, you can also set these values in each contact sensor individually in attribute HomeValueWater once they are added to the HOMEMODE device<br>
      default: water|open|on|yes|1|true
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSpecialLocations'>HomeSpecialLocations</a><br>
      comma separated list of additional locations<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeSpecialModes'>HomeSpecialModes</a><br>
      comma separated list of additional modes<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTextAndAreIs'>HomeTextAndAreIs</a><br>
      pipe separated list of your local translations for 'and', 'are' and 'is'<br>
      default: and|are|is
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTextClosedOpen'>HomeTextClosedOpen</a><br>
      pipe separated list of your local translation for 'closed' and 'open'<br>
      default: closed|open
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTextRisingConstantFalling'>HomeTextRisingConstantFalling</a><br>
      pipe separated list of your local translation for 'rising', 'constant' and 'falling'<br>
      default: rising|constant|falling
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTextNoSmokeSmoke'>HomeTextNoSmokeSmoke</a><br>
      pipe separated list of your local translation for 'no smoke' and 'smoke'<br>
      default: no smoke|smoke
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTextNoTamperTamper'>HomeTextNoTamperTamper</a><br>
      pipe separated list of your local translation for 'not tampered' and 'tampered'<br>
      default: not tampered|tampered
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTextNoWaterWater'>HomeTextNoWaterWater</a><br>
      pipe separated list of your local translation for 'no water' and 'water'<br>
      default: no water|water
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTextTodayTomorrowAfterTomorrow'>HomeTextTodayTomorrowAfterTomorrow</a><br>
      pipe separated list of your local translations for 'today', 'tomorrow' and 'day after tomorrow'<br>
      this is used by weather forecast<br>
      default: today|tomorrow|day after tomorrow
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTextWeatherForecastInSpecDays'>HomeTextWeatherForecastInSpecDays</a><br>
      your text for weather forecast in specific days<br>
      placeholders can be used!<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTextWeatherForecastToday'>HomeTextWeatherForecastToday</a><br>
      your text for weather forecast today<br>
      placeholders can be used!<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTextWeatherForecastTomorrow'>HomeTextWeatherForecastTomorrow</a><br>
      your text for weather forecast tomorrow and the day after tomorrow<br>
      placeholders can be used!<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTextWeatherNoForecast'>HomeTextWeatherNoForecast</a><br>
      your text for no available weather forecast<br>
      default: No forecast available
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTextWeatherLong'>HomeTextWeatherLong</a><br>
      your text for long weather information<br>
      placeholders can be used!<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTextWeatherShort'>HomeTextWeatherShort</a><br>
      your text for short weather information<br>
      placeholders can be used!<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTrendCalcAge'>HomeTrendCalcAge</a><br>
      time in seconds for the max age of the previous measured value for calculating trends<br>
      default: 900
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTriggerAnyoneElseAtHome'>HomeTriggerAnyoneElseAtHome</a><br>
      your anyoneElseAtHome trigger device (device:reading:valueOn:valueOff)<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTriggerPanic'>HomeTriggerPanic</a><br>
      your panic alarm trigger device (device:reading:valueOn[:valueOff])<br>
      valueOff is optional<br>
      valueOn will toggle panic mode if valueOff is not given<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeTwilightDevice'>HomeTwilightDevice</a><br>
      your local Twilight device<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeUserCSS'>HomeUserCSS</a><br>
      CSS code to override the default styling of HOMEMODE<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeUWZ'>HomeUWZ</a><br>
      your local UWZ device<br>
      default:
    </li>
    <li>
      <a id='HOMEMODE-attr-HomeWeatherDevice'>HomeWeatherDevice</a><br>
      your local Weather device<br>
      default:
    </li>
  </ul>
  <br>
  <a id='HOMEMODE-read'></a>
  <p><b>Readings</b></p>
  <ul>
    <li>
      <a id='HOMEMODE-read-alarmSmoke'>alarmSmoke</a><br>
      list of triggered smoke sensors
    </li>
    <li>
      <a id='HOMEMODE-read-alarmSmoke_ct'>alarmSmoke_ct</a><br>
      count of triggered smoke sensors
    </li>
    <li>
      <a id='HOMEMODE-read-alarmSmoke_hr'>alarmSmoke_hr</a><br>
      (human readable) list of triggered smoke sensors
    </li>
    <li>
      <a id='HOMEMODE-read-alarmState'>alarmState</a><br>
      current state of alarm system (includes current alarms - for homebridgeMapping)
    </li>
    <li>
      <a id='HOMEMODE-read-alarmTampered'>alarmTampered</a><br>
      list of names of tampered sensors
    </li>
    <li>
      <a id='HOMEMODE-read-alarmTampered_ct'>alarmTampered_ct</a><br>
      count of tampered sensors
    </li>
    <li>
      <a id='HOMEMODE-read-alarmTampered_hr'>alarmTampered_hr</a><br>
      (human readable) list of tampered sensors
    </li>
    <li>
      <a id='HOMEMODE-read-alarmTriggered'>alarmTriggered</a><br>
      list of triggered alarm sensors (contact/motion sensors)
    </li>
    <li>
      <a id='HOMEMODE-read-alarmTriggered_ct'>alarmTriggered_ct</a><br>
      count of triggered alarm sensors (contact/motion sensors)
    </li>
    <li>
      <a id='HOMEMODE-read-alarmTriggered_hr'>alarmTriggered_hr</a><br>
      (human readable) list of triggered alarm sensors (contact/motion sensors)
    </li>
    <li>
      <a id='HOMEMODE-read-anyoneElseAtHome'>anyoneElseAtHome</a><br>
      anyoneElseAtHome on or off
    </li>
    <li>
      <a id='HOMEMODE-read-anyoneElseAtHomeBy'>anyoneElseAtHomeBy</a><br>
      comma separated list of names which requested the anyoneElseAtHome mode
    </li>
    <li>
      <a id='HOMEMODE-read-contactsDoorsInsideOpen'>contactsDoorsInsideOpen</a><br>
      list of names of open contact sensors of type doorinside
    </li>
    <li>
      <a id='HOMEMODE-read-batteryLow'>batteryLow</a><br>
      list of names of sensors with low battery
    </li>
    <li>
      <a id='HOMEMODE-read-batteryLow_ct'>batteryLow_ct</a><br>
      count of sensors with low battery
    </li>
    <li>
      <a id='HOMEMODE-read-batteryLow_hr'>batteryLow_hr</a><br>
      (human readable) list of sensors with low battery
    </li>
    <li>
      <a id='HOMEMODE-read-contactsDoorsInsideOpen_ct'>contactsDoorsInsideOpen_ct</a><br>
      count of open contact sensors of type doorinside
    </li>
    <li>
      <a id='HOMEMODE-read-contactsDoorsInsideOpen_hr'>contactsDoorsInsideOpen_hr</a><br>
      (human readable) list of open contact sensors of type doorinside
    </li>
    <li>
      <a id='HOMEMODE-read-contactsDoorsMainOpen'>contactsDoorsMainOpen</a><br>
      list of names of open contact sensors of type doormain
    </li>
    <li>
      <a id='HOMEMODE-read-contactsDoorsMainOpen_ct'>contactsDoorsMainOpen_ct</a><br>
      count of open contact sensors of type doormain
    </li>
    <li>
      <a id='HOMEMODE-read-contactsDoorsMainOpen_hr'>contactsDoorsMainOpen_hr</a><br>
      (human readable) list of open contact sensors of type doormain
    </li>
    <li>
      <a id='HOMEMODE-read-contactsDoorsOutsideOpen'>contactsDoorsOutsideOpen</a><br>
      list of names of open contact sensors of type dooroutside
    </li>
    <li>
      <a id='HOMEMODE-read-contactsDoorsOutsideOpen_ct'>contactsDoorsOutsideOpen_ct</a><br>
      count of open contact sensors of type dooroutside
    </li>
    <li>
      <a id='HOMEMODE-read-contactsDoorsOutsideOpen_hr'>contactsDoorsOutsideOpen_hr</a><br>
      (human readable) list of contact sensors of type dooroutside
    </li>
    <li>
      <a id='HOMEMODE-read-contactsOpen'>contactsOpen</a><br>
      list of names of all open contact sensors
    </li>
    <li>
      <a id='HOMEMODE-read-contactsOpen_ct'>contactsOpen_ct</a><br>
      count of all open contact sensors
    </li>
    <li>
      <a id='HOMEMODE-read-contactsOpen_hr'>contactsOpen_hr</a><br>
      (human readable) list of all open contact sensors
    </li>
    <li>
      <a id='HOMEMODE-read-contactsOutsideOpen'>contactsOutsideOpen</a><br>
      list of names of open contact sensors outside (sensor types: dooroutside,doormain,window)
    </li>
    <li>
      <a id='HOMEMODE-read-contactsOutsideOpen_ct'>contactsOutsideOpen_ct</a><br>
      count of open contact sensors outside (sensor types: dooroutside,doormain,window)
    </li>
    <li>
      <a id='HOMEMODE-read-contactsOutsideOpen_hr'>contactsOutsideOpen_hr</a><br>
      (human readable) list of open contact sensors outside (sensor types: dooroutside,doormain,window)
    </li>
    <li>
      <a id='HOMEMODE-read-contactsWindowsOpen'>contactsWindowsOpen</a><br>
      list of names of open contact sensors of type window
    </li>
    <li>
      <a id='HOMEMODE-read-contactsWindowsOpen_ct'>contactsWindowsOpen_ct</a><br>
      count of open contact sensors of type window
    </li>
    <li>
      <a id='HOMEMODE-read-contactsWindowsOpen_hr'>contactsWindowsOpen_hr</a><br>
      (human readable) list of open contact sensors of type window
    </li>
    <li>
      <a id='HOMEMODE-read-daytime'>daytime</a><br>
      current daytime (as configured in HomeDaytimes) - independent from the mode of the HOMEMODE device<br>
    </li>
    <li>
      <a id='HOMEMODE-read-dnd'>dnd</a><br>
      dnd (do not disturb) on or off
    </li>
    <li>
      <a id='HOMEMODE-read-devicesDisabled'>devicesDisabled</a><br>
      comma separated list of disabled devices
    </li>
    <li>
      <a id='HOMEMODE-read-energy'>energy</a><br>
      calculated total energy
    </li>
    <li>
      <a id='HOMEMODE-read-event-' data-pattern='event-.+'>event-&lt;%CALENDAR%&gt;</a><br>
      current event of the CALENDAR device(s)
    </li>
    <li>
      <a id='HOMEMODE-read-humidty'>humidty</a><br>
      current humidty of the Weather device or of your own sensor (if available)
    </li>
    <li>
      <a id='HOMEMODE-read-humidtyTrend'>humidtyTrend</a><br>
      trend of the humidty over the last hour<br>
      possible values: constant, rising, falling
    </li>
    <li>
      <a id='HOMEMODE-read-icawarning'>icawarning</a><br>
      ice warning<br>
      values: 0 if off and 1 if on
    </li>
    <li>
      <a id='HOMEMODE-read-lastAbsentByPresenceDevice'>lastAbsentByPresenceDevice</a><br>
      last presence device which went absent
    </li>
    <li>
      <a id='HOMEMODE-read-lastAbsentByResident'>lastAbsentByResident</a><br>
      last resident who went absent
    </li>
    <li>
      <a id='HOMEMODE-read-lastActivityByPresenceDevice'>lastActivityByPresenceDevice</a><br>
      last active presence device
    </li>
    <li>
      <a id='HOMEMODE-read-lastActivityByResident'>lastActivityByResident</a><br>
      last active resident
    </li>
    <li>
      <a id='HOMEMODE-read-lastAsleepByResident'>lastAsleepByResident</a><br>
      last resident who went asleep
    </li>
    <li>
      <a id='HOMEMODE-read-lastAwokenByResident'>lastAwokenByResident</a><br>
      last resident who went awoken
    </li>
    <li>
      <a id='HOMEMODE-read-lastBatteryNormal'>lastBatteryNormal</a><br>
      last sensor with normal battery
    </li>
    <li>
      <a id='HOMEMODE-read-lastBatteryLow'>lastBatteryLow</a><br>
      last sensor with low battery
    </li>
    <li>
      <a id='HOMEMODE-read-lastCMDerror'>lastCMDerror</a><br>
      last occured error and command(chain) while executing command(chain)
    </li>
    <li>
      <a id='HOMEMODE-read-lastContact'>lastContact</a><br>
      last contact sensor which triggered open
    </li>
    <li>
      <a id='HOMEMODE-read-lastContactClosed'>lastContactClosed</a><br>
      last contact sensor which triggered closed
    </li>
    <li>
      <a id='HOMEMODE-read-lastGoneByResident'>lastGoneByResident</a><br>
      last resident who went gone
    </li>
    <li>
      <a id='HOMEMODE-read-lastGotosleepByResident'>lastGotosleepByResident</a><br>
      last resident who went gotosleep
    </li>
    <li>
      <a id='HOMEMODE-read-lastInfo'>lastInfo</a><br>
      last shown item on infopanel (HomeAdvancedDetails)
    </li>
    <li>
      <a id='HOMEMODE-read-lastMotion'>lastMotion</a><br>
      last sensor which triggered motion
    </li>
    <li>
      <a id='HOMEMODE-read-lastMotionClosed'>lastMotionClosed</a><br>
      last sensor which triggered motion end
    </li>
    <li>
      <a id='HOMEMODE-read-lastPresentByPresenceDevice'>lastPresentByPresenceDevice</a><br>
      last presence device which came present
    </li>
    <li>
      <a id='HOMEMODE-read-lastPresentByResident'>lastPresentByResident</a><br>
      last resident who came present
    </li>
    <li>
      <a id='HOMEMODE-read-light'>light</a><br>
      current light reading value
    </li>
    <li>
      <a id='HOMEMODE-read-location'>location</a><br>
      current location
    </li>
    <li>
      <a id='HOMEMODE-read-luminance'>luminance</a><br>
      average luminance of all motion sensors (if available)
    </li>
    <li>
      <a id='HOMEMODE-read-luminanceTrend'>luminanceTrend</a><br>
      trend of the luminance over the last hour<br>
      possible values: constant, rising, falling
    </li>
    <li>
      <a id='HOMEMODE-read-mode'>mode</a><br>
      current mode
    </li>
    <li>
      <a id='HOMEMODE-read-modeAlarm'>modeAlarm</a><br>
      current mode of alarm system
    </li>
    <li>
      <a id='HOMEMODE-read-motionsInside'>motionsInside</a><br>
      list of names of open motion sensors of type inside
    </li>
    <li>
      <a id='HOMEMODE-read-motionsInside_ct'>motionsInside_ct</a><br>
      count of open motion sensors of type inside
    </li>
    <li>
      <a id='HOMEMODE-read-motionsInside_hr'>motionsInside_hr</a><br>
      (human readable) list of open motion sensors of type inside
    </li>
    <li>
      <a id='HOMEMODE-read-motionsOutside'>motionsOutside</a><br>
      list of names of open motion sensors of type outside
    </li>
    <li>
      <a id='HOMEMODE-read-motionsOutside_ct'>motionsOutside_ct</a><br>
      count of open motion sensors of type outside
    </li>
    <li>
      <a id='HOMEMODE-read-motionsOutside_hr'>motionsOutside_hr</a><br>
      (human readable) list of open motion sensors of type outside
    </li>
    <li>
      <a id='HOMEMODE-read-motionsSensors'>motionsSensors</a><br>
      list of all names of open motion sensors
    </li>
    <li>
      <a id='HOMEMODE-read-motionsSensors_ct'>motionsSensors_ct</a><br>
      count of all open motion sensors
    </li>
    <li>
      <a id='HOMEMODE-read-motionsSensors_hr'>motionsSensors_hr</a><br>
      (human readable) list of all open motion sensors
    </li>
    <li>
      <a id='HOMEMODE-read-power'>power</a><br>
      calculated total power
    </li>
    <li>
      <a id='HOMEMODE-read-prevMode'>prevMode</a><br>
      previous mode
    </li>
    <li>
      <a id='HOMEMODE-read-presence'>presence</a><br>
      presence of any resident
    </li>
    <li>
      <a id='HOMEMODE-read-pressure'>pressure</a><br>
      current air pressure of the Weather device
    </li>
    <li>
      <a id='HOMEMODE-read-prevActivityByResident'>prevActivityByResident</a><br>
      previous active resident
    </li>
    <li>
      <a id='HOMEMODE-read-prevContact'>prevContact</a><br>
      previous contact sensor which triggered open
    </li>
    <li>
      <a id='HOMEMODE-read-prevContactClosed'>prevContactClosed</a><br>
      previous contact sensor which triggered closed
    </li>
    <li>
      <a id='HOMEMODE-read-prevLocation'>prevLocation</a><br>
      previous location
    </li>
    <li>
      <a id='HOMEMODE-read-prevMode'>prevMode</a><br>
      previous mode
    </li>
    <li>
      <a id='HOMEMODE-read-prevMotion'>prevMotion</a><br>
      previous sensor which triggered motion
    </li>
    <li>
      <a id='HOMEMODE-read-prevMotionClosed'>prevMotionClosed</a><br>
      previous sensor which triggered motion end
    </li>
    <li>
      <a id='HOMEMODE-read-prevModeAlarm'>prevModeAlarm</a><br>
      previous alarm mode
    </li>
    <li>
      <a id='HOMEMODE-read-publicIP'>publicIP</a><br>
      last checked public IP address
    </li>
    <li>
      <a id='HOMEMODE-read-season'>season</a><br>
      current season as configured in HomeSeasons<br>
    </li>
    <li>
      <a id='HOMEMODE-read-state'>state</a><br>
      current state
    </li>
    <li>
      <a id='HOMEMODE-read-temperature'>temperature</a><br>
      current temperature of the Weather device or of your own sensor (if available)
    </li>
    <li>
      <a id='HOMEMODE-read-temperatureTrend'>temperatureTrend</a><br>
      trend of the temperature over the last hour<br>
      possible values: constant, rising, falling
    </li>
    <li>
      <a id='HOMEMODE-read-twilight'>twilight</a><br>
      current twilight reading value
    </li>
    <li>
      <a id='HOMEMODE-read-twilightEvent'>twilightEvent</a><br>
      current twilight event
    </li>
    <li>
      <a id='HOMEMODE-read-uwz_warnCount'>uwz_warnCount</a><br>
      current UWZ warn count
    </li>
    <li>
      <a id='HOMEMODE-read-wind'>wind</a><br>
      current wind speed of the Weather device
    </li>
  </ul>
  <a id='HOMEMODE-placeholders'></a>
  <p><b>Placeholders</b></p>
  <p>These placeholders can be used in all HomeCMD attributes</p>
  <ul>
    <li>
      <a id='HOMEMODE-placeholders-%ADDRESS%'>%ADDRESS%</a><br>
      mac address of the last triggered presence device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%ALIAS%'>%ALIAS%</a><br>
      alias of the last triggered resident
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%ALARM%'>%ALARM%</a><br>
      value of the alarmTriggered reading of the HOMEMODE device<br>
      will return 0 if no alarm is triggered or a list of triggered sensors if alarm is triggered
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%ALARMCT%'>%ALARMCT%</a><br>
      value of the alarmTriggered_ct reading of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%ALARMHR%'>%ALARMHR%</a><br>
      value of the alarmTriggered_hr reading of the HOMEMODE device<br>
      will return 0 if no alarm is triggered or a (human readable) list of triggered sensors if alarm is triggered<br>
      can be used for sending msg e.g.
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%AMODE%'>%AMODE%</a><br>
      current alarm mode
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%AEAH%'>%AEAH%</a><br>
      state of anyoneElseAtHome, will return 1 if on and 0 if off
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%ARRIVERS%'>%ARRIVERS%</a><br>
      will return a list of aliases of all registered residents/guests with location arrival<br>
      this can be used to welcome residents after main door open/close<br>
      e.g. Peter, Paul and Marry
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%AUDIO%'>%AUDIO%</a><br>
      audio device of the last triggered resident (attribute msgContactAudio)<br>
      if attribute msgContactAudio of the resident has no value the value is trying to be taken from device globalMsg (if available)<br>
      can be used to address resident specific msg(s) of type audio, e.g. night/morning wishes
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%BE%'>%BE%</a><br>
      is or are of condition reading of monitored Weather device<br>
      can be used for weather (forecast) output
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%BATTERYLOW%'>%BATTERYLOW%</a><br>
      alias (or name if alias is not set) of the last battery sensor which reported low battery
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%BATTERYLOWALL%'>%BATTERYLOWALL%</a><br>
      list of aliases (or names if alias is not set) of all battery sensor which reported low battery currently
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%BATTERYLOWCT%'>%BATTERYLOWCT%</a><br>
      number of battery sensors which reported low battery currently
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%BATTERYNORMAL%'>%BATTERYNORMAL%</a><br>
      alias (or name if alias is not set) of the last battery sensor which reported normal battery
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%CONDITION%'>%CONDITION%</a><br>
      value of the condition reading of monitored Weather device<br>
      can be used for weather (forecast) output
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%CONTACT%'>%CONTACT%</a><br>
      value of the lastContact reading (last opened sensor)
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DEFINED%'>%DEFINED%</a><br>
      name of the previously defined device<br>
      can be used to trigger actions based on the name of the defined device<br>
      only available within HomeCMDfhemDEFINED
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DAYTIME%'>%DAYTIME%</a><br>
      value of the daytime reading of the HOMEMODE device<br>
      can be used to trigger day time specific actions
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DEVICE%'>%DEVICE%</a><br>
      name of the last triggered presence device<br>
      can be used to trigger actions depending on the last present/absent presence device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DEVICEA%'>%DEVICEA%</a><br>
      name of the last triggered absent presence device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DEVICEP%'>%DEVICEP%</a><br>
      name of the last triggered present presence device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DISABLED%'>%DISABLED%</a><br>
      comma separated list of disabled devices
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DND%'>%DND%</a><br>
      state of dnd, will return 1 if on and 0 if off
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DURABSENCE%'>%DURABSENCE%</a><br>
      value of the durTimerAbsence_cr reading of the last triggered resident
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DURABSENCELAST%'>%DURABSENCELAST%</a><br>
      value of the lastDurAbsence_cr reading of the last triggered resident
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DURPRESENCE%'>%DURPRESENCE%</a><br>
      value of the durTimerPresence_cr reading of the last triggered resident
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DURPRESENCELAST%'>%DURPRESENCELAST%</a><br>
      value of the lastDurPresence_cr reading of the last triggered resident
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DURSLEEP%'>%DURSLEEP%</a><br>
      value of the durTimerSleep_cr reading of the last triggered resident
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DURSLEEPLAST%'>%DURSLEEPLAST%</a><br>
      value of the lastDurSleep_cr reading of the last triggered resident
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%CALENDARNAME%'>%CALENDARNAME%</a><br>
      will return the current event of the given calendar name, will return 0 if event is none<br>
      can be used to trigger actions on any event of the given calendar
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%CALENDARNAME-EVENTNAME%'>%CALENDARNAME-EVENTNAME%</a><br>
      will return 1 if given event of given calendar is current, will return 0 if event is not current<br>
      can be used to trigger actions during specific events only (Christmas?)
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%FORECAST%'>%FORECAST%</a><br>
      will return the weather forecast for tomorrow<br>
      can be used in msg or tts
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%FORECASTTODAY%'>%FORECASTTODAY%</a><br>
      will return the weather forecast for today<br>
      can be used in msg or tts
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%HUMIDITY%'>%HUMIDITY%</a><br>
      value of the humidity reading of the HOMEMODE device<br>
      can be used for weather info in HomeTextWeather attributes e.g.
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%HUMIDITYTREND%'>%HUMIDITYTREND%</a><br>
      value of the humidityTrend reading of the HOMEMODE device<br>
      possible values: constant, rising, falling
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%ICE%'>%ICE%</a><br>
      will return 1 if ice warning is on, will return 0 if ice warning is off<br>
      can be used to send ice warning specific msg(s) in specific situations, e.g. to warn leaving residents
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%IP%'>%IP%</a><br>
      value of reading publicIP<br>
      can be used to send msg(s) with (new) IP address
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%LIGHT%'>%LIGHT%</a><br>
      value of the light reading of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%LOCATION%'>%LOCATION%</a><br>
      value of the location reading of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%LOCATIONR%'>%LOCATIONR%</a><br>
      value of the location reading of the last triggered resident
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%LUMINANCE%'>%LUMINANCE%</a><br>
      average luminance of motion sensors (if available)
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%LUMINANCETREND%'>%LUMINANCETREND%</a><br>
      value of the luminanceTrend reading of the HOMEMODE device<br>
      possible values: constant, rising, falling
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%MODE%'>%MODE%</a><br>
      current mode of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%MODEALARM%'>%MODEALARM%</a><br>
      current alarm mode
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%MOTION%'>%MOTION%</a><br>
      value of the lastMotion reading (last opened sensor)
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%NAME%'>%NAME%</a><br>
      name of the HOMEMODE device itself (same as %SELF%)
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%OPEN%'>%OPEN%</a><br>
      value of the contactsOutsideOpen reading of the HOMEMODE device<br>
      can be used to send msg(s) in specific situations, e.g. to warn leaving residents of open contact sensors
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%OPENCT%'>%OPENCT%</a><br>
      value of the contactsOutsideOpen_ct reading of the HOMEMODE device<br>
      can be used to send msg(s) in specific situations depending on the number of open contact sensors, maybe in combination with placeholder %OPEN%
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%OPENHR%'>%OPENHR%</a><br>
      value of the contactsOutsideOpen_hr reading of the HOMEMODE device<br>
      can be used to send msg(s)
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%PANIC%'>%PANIC%</a><br>
      state of panic, will return 1 if on and 0 if off
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%RESIDENT%'>%RESIDENT%</a><br>
      name of the last triggered resident
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%PRESENT%'>%PRESENT%</a><br>
      presence of the HOMEMODE device<br>
      will return 1 if present or 0 if absent
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%PRESENTR%'>%PRESENTR%</a><br>
      presence of last triggered resident<br>
      will return 1 if present or 0 if absent
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%PRESSURE%'>%PRESSURE%</a><br>
      value of the pressure reading of the HOMEMODE device<br>
      can be used for weather info in HomeTextWeather attributes e.g.
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%PREVAMODE%'>%PREVAMODE%</a><br>
      previous alarm mode of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%PREVCONTACT%'>%PREVCONTACT%</a><br>
      previous open contact sensor
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%PREVMODE%'>%PREVMODE%</a><br>
      previous mode of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%PREVMODER%'>%PREVMODER%</a><br>
      previous state of last triggered resident
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%PREVMOTION%'>%PREVMOTION%</a><br>
      previous open motion sensor
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%SEASON%'>%SEASON%</a><br>
      value of the season reading of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%SELF%'>%SELF%</a><br>
      name of the HOMEMODE device itself (same as %NAME%)
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%SENSORSBATTERY%'>%SENSORSBATTERY%</a><br>
      all battery sensors from internal SENSORSBATTERY
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%SENSORSCONTACT%'>%SENSORSCONTACT%</a><br>
      all contact sensors from internal SENSORSCONTACT
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%SENSORSENERGY%'>%SENSORSENERGY%</a><br>
      all energy sensors from internal SENSORSENERGY
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%SENSORSMOTION%'>%SENSORSMOTION%</a><br>
      all motion sensors from internal SENSORSMOTION
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%SENSORSSMOKE%'>%SENSORSSMOKE%</a><br>
      all smoke sensors from internal SENSORSSMOKE
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%SMOKE%'>%SMOKE%</a><br>
      value of the alarmSmoke reading of the HOMEMODE device<br>
      will return 0 if no smoke alarm is triggered or a list of triggered sensors if smoke alarm is triggered
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%SMOKECT%'>%SMOKECT%</a><br>
      value of the alarmSmoke_ct reading of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%SMOKEHR%'>%SMOKEHR%</a><br>
      value of the alarmSmoke_hr reading of the HOMEMODE device<br>
      will return 0 if no smoke  alarm is triggered or a (human readable) list of triggered sensors if smoke alarm is triggered<br>
      can be used for sending msg e.g.
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%TAMPERED%'>%TAMPERED%</a><br>
      value of the sensorsTampered reading of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%TAMPEREDCT%'>%TAMPEREDCT%</a><br>
      value of the sensorsTampered_ct reading of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%TAMPEREDHR%'>%TAMPEREDHR%</a><br>
      value of the sensorsTampered_hr reading of the HOMEMODE device<br>
      can be used for sending msg e.g.
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%TEMPERATURE%'>%TEMPERATURE%</a><br>
      value of the temperature reading of the HOMEMODE device<br>
      can be used for weather info in HomeTextWeather attributes e.g.
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%TEMPERATURETREND%'>%TEMPERATURETREND%</a><br>
      value of the temperatureTrend reading of the HOMEMODE device<br>
      possible values: constant, rising, falling
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%TWILIGHT%'>%TWILIGHT%</a><br>
      value of the twilight reading of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%TWILIGHTEVENT%'>%TWILIGHTEVENT%</a><br>
      current twilight event
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%TOBE%'>%TOBE%</a><br>
      are or is of the weather condition<br>
      useful for phrasing sentences
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%UWZ%'>%UWZ%</a><br>
      UWZ warnings count
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%UWZLONG%'>%UWZLONG%</a><br>
      all current UWZ warnings as long text
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%UWZSHORT%'>%UWZSHORT%</a><br>
      all current UWZ warnings as short text
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%WATER%'>%WATER%</a><br>
      value of the alarmWater reading of the HOMEMODE device<br>
      will return 0 if no water alarm is triggered or a list of triggered sensors if water alarm is triggered
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%WATERCT%'>%WATERCT%</a><br>
      value of the alarmWater_ct reading of the HOMEMODE device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%WATERHR%'>%WATERHR%</a><br>
      value of the alarmWater_hr reading of the HOMEMODE device<br>
      will return 0 if no water alarm is triggered or a (human readable) list of triggered sensors if water alarm is triggered<br>
      can be used for sending msg e.g.
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%WEATHER%'>%WEATHER%</a><br>
      value of 'get &lt;HOMEMODE&gt; weather short'<br>
      can be used for for msg weather info e.g.
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%WEATHERLONG%'>%WEATHERLONG%</a><br>
      value of 'get &lt;HOMEMODE&gt; weather long'<br>
      can be used for for msg weather info e.g.
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%WIND%'>%WIND%</a><br>
      value of the wind reading of the HOMEMODE device<br>
      can be used for weather info in HomeTextWeather attributes e.g.
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%WINDCHILL%'>%WINDCHILL%</a><br>
      value of the apparentTemperature reading of the Weather device<br>
      can be used for weather info in HomeTextWeather attributes e.g.
    </li>
  </ul>
  <p>These placeholders can only be used within HomeTextWeatherForecast attributes</p>
  <ul>
    <li>
      <a id='HOMEMODE-placeholders-%CONDITION%'>%CONDITION%</a><br>
      value of weather forecast condition
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DAY%'>%DAY%</a><br>
      day number of weather forecast
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%HIGH%'>%HIGH%</a><br>
      value of maximum weather forecast temperature
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%LOW%'>%LOW%</a><br>
      value of minimum weather forecast temperature
    </li>
  </ul>
  <p>These placeholders can only be used within HomeCMDcontact, HomeCMDmotion and HomeCMDalarm attributes</p>
  <ul>
    <li>
      <a id='HOMEMODE-placeholders-%ALIAS%'>%ALIAS%</a><br>
      alias of the last triggered contact/motion/smoke sensor
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%SENSOR%'>%SENSOR%</a><br>
      name of the last triggered contact/motion/smoke sensor
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%STATE%'>%STATE%</a><br>
      state of the last triggered contact/motion/smoke sensor
    </li>
  </ul>
  <p>These placeholders can only be used within calendar event related HomeCMDevent attributes</p>
  <ul>
    <li>
      <a id='HOMEMODE-placeholders-%CALENDAR%'>%CALENDAR%</a><br>
      name of the calendar
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%DESCRIPTION%'>%DESCRIPTION%</a><br>
      description of current event of the calendar (not applicable for holiday devices)
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%EVENT%'>%EVENT%</a><br>
      summary of current event of the calendar
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%PREVEVENT%'>%PREVEVENT%</a><br>
      summary of previous event of the calendar
    </li>
  </ul>
  <p>These placeholders can only be used within HomeCMDdeviceDisable and HomeCMDdeviceEnable attributes</p>
  <ul>
    <li>
      <a id='HOMEMODE-placeholders-%DEVICE%'>%DEVICE%</a><br>
      name of the disabled/enabled device
    </li>
    <li>
      <a id='HOMEMODE-placeholders-%ALIAS%'>%ALIAS%</a><br>
      alias of the disabled/enabled device
    </li>
  </ul>
</ul>

=end html

=for :application/json;q=META.json 22_HOMEMODE.pm
{
  "abstract": "home device with ROOMMATE/GUEST/PET integration and much more",
  "x_lang": {
    "de": {
      "abstract": ""
    }
  },
  "keywords": [
    "fhem-core",
    "automation",
    "alarm",
    "integration",
    "wow"
  ],
  "release_status": "beta",
  "license": "GPL_2",
  "version": "v2.0.0",
  "author": [
    "DeeSPe <ds@deespe.com>"
  ],
  "x_fhem_maintainer": [
    "DeeSPe"
  ],
  "x_fhem_maintainer_github": [
    "DeeSPe"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 6.0,
        "perl": 5.016,
        "Meta": 0,
        "JSON": 0
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut