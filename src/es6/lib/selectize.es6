import $ from "jquery/dist/jquery";
import "selectize/dist/js/selectize";

const domLoaded = () => {
  enableSelectize();
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
} else {
  domLoaded();
}

const enableSelectize = () => {
  $(".selectize").each((index, elem) => {
    let $elem = $(elem);

    let option = {};
    if ($elem.data("placeholder")) option.placeholder = $elem.data("placeholder");
    if ($elem.data("create")) option.create = $elem.data("create");

    $elem.selectize(option);
  });
};

// javascript - selectize causes keyboard to appear on Android - Stack Overflow
// https://stackoverflow.com/questions/28510878/selectize-causes-keyboard-to-appear-on-android/30087408
const fixSelectizeReadonly = (selectorList) => {
  for (let selector of selectorList) {
    $(`${selector} + .selectize-control .selectize-input input`).attr("readonly", "readonly");
  }
};

export default { fixSelectizeReadonly };
