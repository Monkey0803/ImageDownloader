/** Menu data shared by the trigger and the AppMenu renderer. */
export class MenuItemSpec {
  readonly id: string;
  readonly label: string;
  readonly action: () => void;
  icon: string = '';
  danger: boolean = false;
  enabled: boolean = true;

  constructor(id: string, label: string, action: () => void) {
    this.id = id;
    this.label = label;
    this.action = action;
  }

  withIcon(icon: string): MenuItemSpec { this.icon = icon; return this; }
  markDanger(): MenuItemSpec { this.danger = true; return this; }
  withEnabled(enabled: boolean): MenuItemSpec { this.enabled = enabled; return this; }
}

export class MenuSpec {
  readonly items: MenuItemSpec[];
  readonly width: number;

  constructor(items: MenuItemSpec[], width: number = 248) {
    this.items = items;
    this.width = width;
  }
}
