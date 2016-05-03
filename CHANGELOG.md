## 1.0.0+1

More robust notify: will not break your app if something goes wrong while notifying a property (i.e. there's some problem
with side effects caused by the propery change).

## 1.0.0-rc.10

Updated to support `polymer-1.0.0-rc.10`. Just check out [this](https://github.com/dart-lang/polymer-dart/issues/665).

## 1.0.0-rc.9

Fixes for lists with native types.

## 1.0.0-rc.8+1

Experimental introducing support for `Observable` `PolymerElement` used as an `@observable` property.

## 1.0.0-rc.8  

Upgrade to `polymer 1.0.0-rc.8`. Changed reference to `observe` git repo in deps to be more compliant to de facto convetion for bare repos reference.

See `demo` project to see how to specify deps (BTW until `polymer_elements` get upgraded too you need to specify a dependency override for reflectable).
