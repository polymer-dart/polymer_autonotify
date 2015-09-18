library elys.auto_notify;

import "package:polymer/polymer.dart";
import "package:observe/observe.dart";
import "package:smoke/smoke.dart";
import "package:logging/logging.dart";

class ObservablePolymerNotifier {

  static final Logger _logger = new Logger("polymer.auto.notify");

  String _path="";
  PolymerElement _element;
  Observable _target;
  StreamSubscription _sub;

  Map<String,ObservablePolymerNotifier> _subNotifiers = {};

  ObservablePolymerNotifier(PolymerElement element, var target,[String path=""]) {
    _element = element;
    _path = path;
    _target = target;

    if (target is Observable) {
      _sub = target.changes.listen((List<ChangeRecord> recs) {
        recs.where((ChangeRecord cr) => cr is PropertyChangeRecord).forEach((PropertyChangeRecord pcr) {
          var val = pcr.newValue;
          _notifySymbol(symbolToName(pcr.name), val);
        });
      });
    } else if (target is ObservableList) {
      _sub = (target as ObservableList).listChanges.listen((List<ListChangeRecord> rc){

        // Notify splice
        rc.forEach((ListChangeRecord lc) {

          _notifySplice(target,"${_path}${symbolToName(pcr.name)}",lc.index,lc.addedCount,lc.removed);
          // Fix observers
          if(lc.removed!=null) {
            for(int i=0;i<lc.removed.length;i++) {
              _subNotifiers.remove((lc.index+i).toString()).close();
            }
            // fix path on the rest
            for (int i=lc.index;i<target.length;i++) {
              _subNotifiers[i.toString()]=_subNotifiers.remove((i+lc.removed.length).toString())
                .._path="${_path}${symbolToName(pcr.name)}.${i}";
            }

          }
          if (lc.addedCount>0) {
            // Fix path on tail
            for (int i=lc.index+lc.addedCount;i<target.length;i++) {
              _subNotifiers[i.toString()] =_subNotifiers.remove((i-lc.addedCount).toString())
                .._path="${_path}${symbolToName(pcr.name)}.${i}";
            }

            // Add new observers
            for (int i=lc.index;i<lc.addedCount+lc.index;i++) {
              _notifySymbol(i.toString(),target[i]);
            }
          }


        });

      });
    }

    // Add Sub

    if (target is List) {
      for (int i=0;i<target.length;i++) {
        _notifySplice(target,"${_path}".substring(0,_path.length-1),0,target.length,target);
        _notifySymbol(i.toString(),target[i],true);
      }
    } else {
      List<Declaration> fields = query(target.runtimeType,new QueryOptions(includeFields:true,includeProperties:true,includeInherited:false));
      fields.where((Declaration f) => f.annotations.any((a)=> a is ObservableProperty)).forEach((Declaration f) {
        var fieldValue=read(target,f.name);
        _notifySymbol(symbolToName(f.name),fieldValue);
      });
    }
  }

  void _notifySymbol(String name,var value,[bool onlyInstall=false]) {
    String path = "${_path}${name}";
    if (!onlyInstall) {
      _logger.fine("Notify ${path} with ${value} for ${_element}");
      if (value!=null)
      _element.notifyPath(path,value);
    }
    _installSubNotifier(name,value);
  }

  void _installSubNotifier(String name,var target) {
    // Attach a new sub notifier for observable objects

    ObservablePolymerNotifier subNotifier = _subNotifiers[name];
    if (subNotifier!=null) {
      subNotifier.close();
    }
    String subPath = "${_path}${name}";
    if (target!=null && (target is Observable || target is List)) {
      _logger.fine("Installing subnotifier for ${name} with ${target}");
      subNotifier = new ObservablePolymerNotifier(_element,target,"${subPath}.");
      _subNotifiers[name] = subNotifier;
    }

  }

  void  close() {
    _subNotifiers.values.forEach((ObservablePolymerNotifier x) => x.close());
    _subNotifiers.clear();
    if (_sub!=null) {
      _sub.cancel();
      _sub=null;
    }
  }


  void _notifySplice(List array, String path, int index, int added, List removed) =>
    _element.jsElement.callMethod('_notifySplice', [jsValue(array),path,index,added, jsValue(removed)]);


}

@behavior
abstract class PolymerAutoNotifySupportMixin  {
  ObservablePolymerNotifier _observablePolymerNotifier;


  static created(mixin) {
    print("MIXIN CREATED CALLED !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!11");
  }

  void attached() {
    _observablePolymerNotifier = new ObservablePolymerNotifier(this,this);
  }

  void detached() {
    _observablePolymerNotifier.close();
    _observablePolymerNotifier=null;
  }

}