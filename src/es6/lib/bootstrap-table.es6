import $ from "jquery/dist/jquery";
import "bootstrap-table/dist/bootstrap-table";
import "bootstrap-table/dist/locale/bootstrap-table-en-US";
import "bootstrap-table/dist/locale/bootstrap-table-ko-KR";

const domLoaded = () => {
  // code here

};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
}
else {
  domLoaded();
}
