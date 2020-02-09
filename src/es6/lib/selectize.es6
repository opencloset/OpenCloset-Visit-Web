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
