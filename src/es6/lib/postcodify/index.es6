window.POSTCODIFY_NO_CSS = true;
import "./search";

const domLoaded = () => {
  // code here
  loadPostcodify(".postcodify");
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
} else {
  domLoaded();
}

const loadPostcodify = (elem) => {
  let $elem = $(elem);
  $elem.postcodifyPopUp({
    api: $elem.data("url"),
  });
};
