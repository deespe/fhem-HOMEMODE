
FW_version["homemode.js"] = "$Id: homemode.js 26813 2022-12-07 21:19:57Z DeeSPe $";

$(FW_HomeModeReadyFn);

const translations = {
  "EN": [
    "Can't delete this attribute because it is not set!",
    "Invalid value!<br>Must be a single number (seconds) or three space separated numbers (seconds)<br>for each alarm mode individually (armaway armnight armhome).",
    "Invalid value!<br>This should be the maximum number how often open warnings should be repeated.",
    "Invalid value!<br>You have to provide space separated numbers, e.g. 5 10 15 17.5",
    "Invalid value!<br>You have to provide space separated numbers for each season in order of the seasons provided in attribute HomeSeasons, e.g. 2 1 2 3.333",
    "Invalid value!<br>Must be a single word.",
    "Invalid value!<br>You have to provide a regex of matching values.",
    "Invalid value!<br>You have to provide a single number, but not 0, p.e. 1000 or 0.001!",
    "Invalid value!<br>Must be a number with max. 2 digits greater than 4.",
    "The choosen attribut will be deleted without asking if it was set already",
    "hide internals and readings",
    "show internals and readings"
  ],
  "DE": [
    "Kann dieses Attribut nicht löschen weil es nicht gesetzt ist!",
    "Ungültiger Wert!<br>Muss eine einzelne Zahl (Sekunden) oder 3 leerzeichenseparierte Zahlen (Sekunden)<br>für jeden Alarmmodus individuell (armaway armnight armhome).",
    "Ungültiger Wert!<br>Das ist die maximale Anzahl wie oft Offenwarnungen wiederholt werden sollen.",
    "Ungültiger Wert!<br>Es sind nur leerzeichenseparierte Zahlen erlaubt, z.B. 5 10 15 17.5",
    "Ungültiger Wert!<br>Es sind nur leerzeichenseparierte Zahlen erlaubt, eine für jede Jahreszeit die im Attribut HomeSeasons gesetzt wurden, z.B. 2 1 2 3.333",
    "Ungültiger Wert!<br>Es ist nur ein einzelnes Wort erlaubt.",
    "Ungültiger Wert!<br>Erlaubt ist nur ein Regex für passende Werte.",
    "Ungültiger Wert!<br>Es ist nur eine einzelne Zahl erlaubt, aber nicht 0, z.B. 1000 or 0.001!",
    "Ungültiger Wert!<br>Muss eine Zahl mit maximal 2 Stellen und größer als 4 sein.",
    "Das ausgewählte Attribut wird ohne Nachfrage gelöscht sofern es gesetzt ist.",
    "Verstecke Internals und Readings",
    "Zeige Internals und Readings"
  ]
};

/*! js-cookie v3.0.1 | MIT */
!function(e,t){"object"==typeof exports&&"undefined"!=typeof module?module.exports=t():"function"==typeof define&&define.amd?define(t):(e=e||self,function(){var n=e.Cookies,o=e.Cookies=t();o.noConflict=function(){return e.Cookies=n,o}}())}(this,(function(){"use strict";function e(e){for(var t=1;t<arguments.length;t++){var n=arguments[t];for(var o in n)e[o]=n[o]}return e}return function t(n,o){function r(t,r,i){if("undefined"!=typeof document){"number"==typeof(i=e({},o,i)).expires&&(i.expires=new Date(Date.now()+864e5*i.expires)),i.expires&&(i.expires=i.expires.toUTCString()),t=encodeURIComponent(t).replace(/%(2[346B]|5E|60|7C)/g,decodeURIComponent).replace(/[()]/g,escape);var c="";for(var u in i)i[u]&&(c+="; "+u,!0!==i[u]&&(c+="="+i[u].split(";")[0]));return document.cookie=t+"="+n.write(r,t)+c}}return Object.create({set:r,get:function(e){if("undefined"!=typeof document&&(!arguments.length||e)){for(var t=document.cookie?document.cookie.split("; "):[],o={},r=0;r<t.length;r++){var i=t[r].split("="),c=i.slice(1).join("=");try{var u=decodeURIComponent(i[0]);if(o[u]=n.read(c,u),e===u)break}catch(e){}}return e?o[e]:o}},remove:function(t,n){r(t,"",e({},n,{expires:-1}))},withAttributes:function(n){return t(this.converter,e({},this.attributes,n))},withConverter:function(n){return t(e({},this.converter,n),this.attributes)}},{attributes:{value:Object.freeze(o)},converter:{value:Object.freeze(n)}})}({read:function(e){return'"'===e[0]&&(e=e.slice(1,-1)),e.replace(/(%[\dA-F]{2})+/gi,decodeURIComponent)},write:function(e){return encodeURIComponent(e).replace(/%(2[346BF]|3[AC-F]|40|5[BDE]|60|7[BCD])/g,decodeURIComponent)}},{path:"/"})}));


function FW_HomeModeReadyFn() {
  var maindev = $("#HOMEMODE").attr("devname");
  if (!maindev)
    return;
  var lang = $("#HOMEMODE").attr("lang")=="DE"?translations.DE:translations.EN;
  var prefix = maindev+'-';
  // fill info panel
  var lastInfo = Cookies.get(prefix+'lastInfo');
  if (lastInfo){
    $('#HOMEMODE_infopanel').html('').css('width',0);
    $('#HOMEMODE_infopanelh').text($('#HOMEMODE').find('[informid='+maindev+'-'+lastInfo+']').first().attr('header'));
    $('#HOMEMODE_infopanel').html($('#HOMEMODE').find('[informid='+maindev+'-'+lastInfo+']').first().html()).attr('informid',maindev+'-'+lastInfo).css('width',$('#HOMEMODE').width());
  }
  $(".HOMEMODE_i").unbind().click(function() {
    var t  = $(this).find(".HOMEMODE_info").text();
    var id = $(this).find(".HOMEMODE_info").attr("informid");
    var r  = id.split("-")[1];
    $("#HOMEMODE_infopanel").html('').width($(this).parent().width()).html(t).attr("informid",id);
    $("#HOMEMODE_infopanelh").text($(this).find(".HOMEMODE_info").attr("header"));
    if (r)
      Cookies.set(prefix+'lastInfo',r);
  });
  // hide/show internals and readings
  $(".HOMEMODE_internals").unbind().click(function() {
    var int = $('.internals');
    var rea = $('.readings');
    if (int.is(':hidden')) {
      int.show();
      rea.show();
      $(this).text(lang[10]).removeClass('active');
      Cookies.remove(prefix+'internalsHide');
    } else {
      int.hide();
      rea.hide();
      $(this).text(lang[11]).addClass('active');
      Cookies.set(prefix+'internalsHide',1);
    }
    return false;
  });
  if (Cookies.get(prefix+'internalsHide'))
    $(".HOMEMODE_internals").trigger('click');
  // $('.attr.downText').parent().find('select').next().after('<a id="HOMEMODE-attr-delete" class="attr" title="'+lang[9]+'" href="#">deleteattr</a>');
  $('.attr.downText').parent().find('select').next().after('<input type="submit" id="HOMEMODE-attr-delete" value="deleteattr" class="attr" title="'+lang[9]+'">');
  $("#HOMEMODE-attr-delete").unbind().click(function() {
    var par = $(this).parent();
    var atr = par.find("select option:selected").val();
    var url = "fhem?cmd=jsonlist2%20"+maindev+"%20"+atr+addcsrf("")+"&XHR=1";
    $.getJSON(url,function(data) {
      var res = data.Results[0].Attributes[atr];
      if (res) {
        FW_delete('deleteattr '+maindev+' '+atr);
        return false;
      } else {
        FW_okDialog(lang[0]);
        return false;
      }
    });
  });
  $('.HOMEMODE_table').find('.add').unbind().click(function(){
    var type = $(this).parent().parent().parent().parent().attr('id').split('-')[1];
    HOMEMODE_addDevice(type);
    return false;
  });
  function HOMEMODE_addDevice(type)
  {
    var div = $('<div>');
    var attr = 'HomeSensors'+type;
    var val = $('.attributes').find('.dname').find('a:contains("'+attr+'")').parent().parent().parent().find('.dval').html();
    if (val.match(/^\.[\*\+]$/i))
      return FW_okDialog('No need to add more sensors because you already applied all device');
    $(div).html('Add sensor '+type.toLowerCase()+':<br><br><input type="text" size="30" value="" placeholder="comma seperated list">');
    $('body').append(div);
    $(div).dialog({
      dialogClass:'no-close', modal:true, width:'auto', closeOnEscape:true, 
      maxWidth:$(window).width()*0.9, maxHeight:$(window).height()*0.9,
      buttons: [
        {text:'Add', click:function(){
          if(!type.match(/^[a-z0-9._]+(,[a-z0-9._]+)*?$/i))
            return FW_okDialog('Illegal characters in the name(s)');
          var nn = $(div).find('input').val();
          var arr = nn.split(',');
          arr.forEach(function(e){
            alert(e);
            $.getJSON("fhem?cmd=jsonlist2%20"+e+addcsrf("")+"&XHR=1",function(data) {
              var res = data.totalResultsReturned;
              if (res != 1) {
                return FW_okDialog('Device '+e+' is not defined');
              }
              var nval = val+','+nn;
              alert(nval);
            });
          });
          // return false;
          // location.href=addcsrf(FW_root+'?cmd=attr '+maindev+' HomeSensors'+$type+'&detail='+maindev);
        }},
        {text:'Cancel', click:doClose} ],
      close: doClose
    });

    function doClose()
    {
      $(this).dialog('close');
      $(div).remove();
      return false;
    }
  }
  $(".HOMEMODE_button").unbind().click(function() {
    var id = $(this).attr("id");
    var kt = $("#"+id+"-table");
    if (kt.is(":hidden"))
    {
      $(".HOMEMODE_table").hide();
      $(".HOMEMODE_button.active").removeClass('active');
      kt.show();
      $(this).addClass('active');
      Cookies.set(prefix+'panel',id);
    } else {
      $(".HOMEMODE_button.active").removeClass('active');
      kt.hide();
      Cookies.remove(prefix+'panel');
    }
  });
  var panel = Cookies.get(prefix+'panel');
  if (panel)
    $('#'+panel).trigger('click');
  $("input[name=HomeActive]").unbind().change(function() {
    var name = $(this).parent().parent().parent().find("input[name=devname]").val();
    var check = $("#content").find("input[name=devname]");
    var st = "En";
    var se = false;
    if ($(this).is(":checked")) {
      st = "Dis";
      se = true;
    }
    $.post(window.location.pathname+"?cmd=set%20"+maindev+"%20device"+st+"able%20"+name+addcsrf(""));
    check.each(function() {
      if ($(this).val() === name)
        $(this).parent().parent().find("input[name=HomeActive]").prop("checked",se)
    });
  });
  var checkboxes = ["HomeModeAlarmActive","HomeOpenDontTriggerModes","HomeOpenDontTriggerModesResidents"];
  checkboxes.forEach(function(a) {
    $("input[name="+a+"]").unbind().change(function() {
      var name = $(this).parent().parent().parent().find("input[name=devname]").val();
      var attr = [];
      $(this).parent().parent().find("input[name="+a+"]:checked").each(function() {
        attr.push($(this).val());
      });
      var as = attr.join("|");
      if (as != "") {
        $.post(window.location.pathname+"?cmd=attr%20"+name+"%20"+a+"%20"+as+addcsrf(""));
      } else {
        $.post(window.location.pathname+"?cmd=deleteattr%20"+name+"%20"+a+addcsrf(""));
      }
    });
  });
  var checkbox = ["HomeAllowNegativeEnergy","HomeAllowNegativePower"];
  checkbox.forEach(function(a) {
    $("input[name="+a+"]").unbind().change(function() {
      var name = $(this).parent().parent().parent().find("input[name=devname]").val();
      if ($(this).is(":checked")) {
        $.post(window.location.pathname+"?cmd=attr%20"+name+"%20"+a+"%201"+addcsrf(""));
      } else {
        $.post(window.location.pathname+"?cmd=deleteattr%20"+name+"%20"+a+addcsrf(""));
      }
    });
  });
  var dropdowns = ["HomeSensorLocation","HomeContactType"];
  dropdowns.forEach(function(a) {
    $("select[name="+a+"]").unbind().change(function() {
      var name = $(this).parent().parent().parent().find("input[name=devname]").val();
      var v = $(this).val();
      $.post(window.location.pathname+"?cmd=attr%20"+name+"%20"+a+"%20"+v+addcsrf(""));
    });
  });
  var inputs = ["HomeAlarmDelay","HomeOpenMaxTrigger","HomeOpenTimeDividers","HomeOpenTimes","HomeReadingContact","HomeValueContact","HomeReadingMotion","HomeValueMotion","HomeReadingTamper","HomeValueTamper","HomeReadingSmoke","HomeValueSmoke","HomeReadingBattery","HomeBatteryLowPercentage","HomeReadingEnergy","HomeDividerEnergy","HomeReadingPower","HomeDividerPower","HomeReadingWater","HomeValueWater","HomeReadingLuminance","HomeDividerLuminance"];
  inputs.forEach(function(inp) {
    $("input[name="+inp+"]").unbind().attr("preval",function() {
      return $(this).val();
    }).on("keypress",function(pre) {
      if (pre.which === 13) {
        // enter was pressed
        var name = $(this).parent().parent().find("input[name=devname]").val();
        var read = $(this).val();
        var url = "fhem?cmd=jsonlist2%20"+name+"%20"+read+addcsrf("")+"&XHR=1";
        var inf = maindev+"-"+name+"."+read;
        var up = $(this).parent().find(".HOMEMODE_read").first();
        var pv = $(this).attr("prevalue");
        var gv = $(this).attr("placeholder");
        // remove leading zeros from numbers
        if (inp === "HomeBatteryLowPercentage" && read.match(/^0+/)) {
          read = parseInt(read);
          $(this).val(read);
        }
        // input not empty and imput not equal placeholder
        if (read !== "" && read !== gv) {
          // inputs validations
          if (inp === "HomeAlarmDelay" && !read.match(/^\d{1,3}((\s\d{1,3}){2})?$/)) {
            FW_okDialog(lang[1]);
          } else if (inp === "HomeOpenMaxTrigger" && !read.match(/^\d{1,2}$/)) {
            FW_okDialog(lang[2]);
          } else if (inp === "HomeOpenTimes" && !read.match(/^\d{1,4}(\.\d)?((\s\d{1,4}(\.\d)?)?){0,}$/)) {
            FW_okDialog(lang[3]);
          } else if (inp === "HomeOpenTimeDividers" && !read.match(/^\d{1,2}(\.\d{1,3})?(\s\d{1,2}(\.\d{1,3})?){0,}$/)) {
            FW_okDialog(lang[4]);
          } else if (inp.match(/^HomeReading/) && !read.match(/^([\w\-\.]+)$/)) {
            FW_okDialog(lang[5]);
          } else if (inp.match(/^HomeValue/) && !read.match(/^\w+(\|\w+){0,}$/)) {
            FW_okDialog(lang[6]);
          } else if (inp.match(/^HomeDivider(Energy|Power|Luminance)$/) && !read.match(/^(?!0)\d+(\.\d+)?$/)) {
            FW_okDialog(lang[7]);
          } else if (inp === "HomeBatteryLowPercentage" && (!String(read).match(/^([1-9]?\d)$/) || read < 5)) {
            FW_okDialog(lang[8]);
          } else {
            // set attribute
            $.post(window.location.pathname+"?cmd=attr%20"+name+"%20"+inp+"%20"+read+addcsrf(""));
            $(this).attr("preval",read);
            // 
            if (inp === "HomeReadingBattery") {
              // hide/show HomeBatteryLowPercentage
              $.getJSON(url,function(data) {
                var res = data.Results[0].Readings[read];
                if (res) {
                  // and apply its value to preview and show HomeBatteryLowPercentage
                  up.text(res.Value).attr("informid",inf).parent().parent().find("input[name=HomeBatteryLowPercentage]").show();
                } else {
                  // or set preview to n.a. and hide HomeBatteryLowPercentage
                  up.text("--").parent().parent().find("input[name=HomeBatteryLowPercentage]").hide();
                }
              });
            }
          }
        } else if ((pv != "" && read == "") || read == gv) {
          $.post(window.location.pathname+"?cmd=deleteattr%20"+name+"%20"+inp+addcsrf(""));
          $(this).attr("preval",read);
          // reset input if value and placeholder are the same
          if (read === gv)
            $(this).val("");
        }
        // set reading to placeholder if reading is empty
        if (read == "") {
          read = gv;
        }
        url = "fhem?cmd=jsonlist2%20"+name+"%20"+read+addcsrf("")+"&XHR=1";
        inf = maindev+"-"+name+"."+read;
        var blp = up.parent().parent().find("input[name=HomeBatteryLowPercentage]");
        // check if reading exists
        if (inp.match(/^HomeReading(Battery|Contact|Motion|Smoke|Tamper|Water|Energy|Power|Luminance)$/)) {
          $.getJSON(url,function(data) {
            var res = data.Results[0].Readings[read];
            if (res) {
              // and apply its value to preview
              up.text(res.Value).attr("informid",inf);
              if (inp === "HomeReadingBattery") {
                // hide/show HomeBatteryLowPercentage
                if (res.Value.match(/^\d{1,3}/)) {
                  blp.show();
                } else {
                  blp.hide();
                }
              }
            } else {
              // or set preview to n.a.
              up.text("--");
            }
          });
        }
      }
    });
  });
};
