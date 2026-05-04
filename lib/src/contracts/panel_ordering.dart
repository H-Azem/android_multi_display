enum PanelSortKey {
  area,
  width,
  height,
  id,
  name,
}

enum PanelSortDirection {
  ascending,
  descending,
}

class PanelOrdering {
  const PanelOrdering({
    this.key = PanelSortKey.area,
    this.direction = PanelSortDirection.descending,
  });

  final PanelSortKey key;
  final PanelSortDirection direction;
}
