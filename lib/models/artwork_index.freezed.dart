// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'artwork_index.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ArtworkIndex {

 List<ArtworkSummary> get artworks;
/// Create a copy of ArtworkIndex
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ArtworkIndexCopyWith<ArtworkIndex> get copyWith => _$ArtworkIndexCopyWithImpl<ArtworkIndex>(this as ArtworkIndex, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ArtworkIndex&&const DeepCollectionEquality().equals(other.artworks, artworks));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(artworks));

@override
String toString() {
  return 'ArtworkIndex(artworks: $artworks)';
}


}

/// @nodoc
abstract mixin class $ArtworkIndexCopyWith<$Res>  {
  factory $ArtworkIndexCopyWith(ArtworkIndex value, $Res Function(ArtworkIndex) _then) = _$ArtworkIndexCopyWithImpl;
@useResult
$Res call({
 List<ArtworkSummary> artworks
});




}
/// @nodoc
class _$ArtworkIndexCopyWithImpl<$Res>
    implements $ArtworkIndexCopyWith<$Res> {
  _$ArtworkIndexCopyWithImpl(this._self, this._then);

  final ArtworkIndex _self;
  final $Res Function(ArtworkIndex) _then;

/// Create a copy of ArtworkIndex
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? artworks = null,}) {
  return _then(_self.copyWith(
artworks: null == artworks ? _self.artworks : artworks // ignore: cast_nullable_to_non_nullable
as List<ArtworkSummary>,
  ));
}

}


/// Adds pattern-matching-related methods to [ArtworkIndex].
extension ArtworkIndexPatterns on ArtworkIndex {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ArtworkIndex value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ArtworkIndex() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ArtworkIndex value)  $default,){
final _that = this;
switch (_that) {
case _ArtworkIndex():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ArtworkIndex value)?  $default,){
final _that = this;
switch (_that) {
case _ArtworkIndex() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<ArtworkSummary> artworks)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ArtworkIndex() when $default != null:
return $default(_that.artworks);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<ArtworkSummary> artworks)  $default,) {final _that = this;
switch (_that) {
case _ArtworkIndex():
return $default(_that.artworks);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<ArtworkSummary> artworks)?  $default,) {final _that = this;
switch (_that) {
case _ArtworkIndex() when $default != null:
return $default(_that.artworks);case _:
  return null;

}
}

}

/// @nodoc


class _ArtworkIndex implements ArtworkIndex {
  const _ArtworkIndex({final  List<ArtworkSummary> artworks = const <ArtworkSummary>[]}): _artworks = artworks;
  

 final  List<ArtworkSummary> _artworks;
@override@JsonKey() List<ArtworkSummary> get artworks {
  if (_artworks is EqualUnmodifiableListView) return _artworks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_artworks);
}


/// Create a copy of ArtworkIndex
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ArtworkIndexCopyWith<_ArtworkIndex> get copyWith => __$ArtworkIndexCopyWithImpl<_ArtworkIndex>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ArtworkIndex&&const DeepCollectionEquality().equals(other._artworks, _artworks));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_artworks));

@override
String toString() {
  return 'ArtworkIndex(artworks: $artworks)';
}


}

/// @nodoc
abstract mixin class _$ArtworkIndexCopyWith<$Res> implements $ArtworkIndexCopyWith<$Res> {
  factory _$ArtworkIndexCopyWith(_ArtworkIndex value, $Res Function(_ArtworkIndex) _then) = __$ArtworkIndexCopyWithImpl;
@override @useResult
$Res call({
 List<ArtworkSummary> artworks
});




}
/// @nodoc
class __$ArtworkIndexCopyWithImpl<$Res>
    implements _$ArtworkIndexCopyWith<$Res> {
  __$ArtworkIndexCopyWithImpl(this._self, this._then);

  final _ArtworkIndex _self;
  final $Res Function(_ArtworkIndex) _then;

/// Create a copy of ArtworkIndex
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? artworks = null,}) {
  return _then(_ArtworkIndex(
artworks: null == artworks ? _self._artworks : artworks // ignore: cast_nullable_to_non_nullable
as List<ArtworkSummary>,
  ));
}


}

// dart format on
