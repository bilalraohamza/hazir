import 'package:material_ui/material_ui.dart' show IconData;
import 'package:phosphor_flutter/phosphor_flutter.dart';

const categoryIconChoices = <String, ({String label, IconData icon})>{
  'forkKnife': (label: 'Food', icon: PhosphorIconsDuotone.forkKnife),
  'coffee': (label: 'Coffee', icon: PhosphorIconsDuotone.coffee),
  'bus': (label: 'Bus', icon: PhosphorIconsDuotone.bus),
  'train': (label: 'Train', icon: PhosphorIconsDuotone.train),
  'airplane': (label: 'Airplane', icon: PhosphorIconsDuotone.airplane),
  'house': (label: 'Home', icon: PhosphorIconsDuotone.house),
  'lightning': (label: 'Electricity', icon: PhosphorIconsDuotone.lightning),
  'wifiHigh': (label: 'Internet', icon: PhosphorIconsDuotone.wifiHigh),
  'phone': (label: 'Phone', icon: PhosphorIconsDuotone.phone),
  'shoppingBag': (label: 'Shopping', icon: PhosphorIconsDuotone.shoppingBag),
  'tShirt': (label: 'Clothing', icon: PhosphorIconsDuotone.tShirt),
  'bookOpen': (label: 'Books', icon: PhosphorIconsDuotone.bookOpen),
  'graduationCap': (
    label: 'Education',
    icon: PhosphorIconsDuotone.graduationCap,
  ),
  'firstAidKit': (label: 'First aid', icon: PhosphorIconsDuotone.firstAidKit),
  'pill': (label: 'Medicine', icon: PhosphorIconsDuotone.pill),
  'barbell': (label: 'Fitness', icon: PhosphorIconsDuotone.barbell),
  'filmStrip': (label: 'Film', icon: PhosphorIconsDuotone.filmStrip),
  'gameController': (label: 'Games', icon: PhosphorIconsDuotone.gameController),
  'gift': (label: 'Gift', icon: PhosphorIconsDuotone.gift),
  'heart': (label: 'Heart', icon: PhosphorIconsDuotone.heart),
  'paperPlaneTilt': (
    label: 'Sending',
    icon: PhosphorIconsDuotone.paperPlaneTilt,
  ),
  'piggyBank': (label: 'Savings', icon: PhosphorIconsDuotone.piggyBank),
  'receipt': (label: 'Receipt', icon: PhosphorIconsDuotone.receipt),
  'tag': (label: 'Tag', icon: PhosphorIconsDuotone.tag),
};

IconData categoryIcon(String key) =>
    categoryIconChoices[key]?.icon ??
    switch (key) {
      'shoppingCart' => PhosphorIconsDuotone.shoppingCart,
      'dotsThree' => PhosphorIconsDuotone.dotsThree,
      'users' => PhosphorIconsDuotone.users,
      'briefcase' => PhosphorIconsDuotone.briefcase,
      'arrowUUpLeft' => PhosphorIconsDuotone.arrowUUpLeft,
      _ => PhosphorIconsDuotone.tag,
    };
