/* BROKEN: the .d.ts exists but does not declare this function (R5),
   and the icon name is not in the generated map (R11). */
import { Icon } from "../controls/Icon";

export function Other() {
  return <Icon name="definitely_not_an_icon" size={24} />;
}
