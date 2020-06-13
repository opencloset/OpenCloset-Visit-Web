import "./lib/import-jquery";
import moment from "moment/src/moment";
import selectize from "./lib/selectize";
import session from "./lib/session";

const pageId = "offorder1";

const domLoaded = () => {
  if (!$(`#page-${pageId}`).length) return;

  selectize.fixSelectizeReadonly(["#offorder1WearSelf", "#offorder1WearGender", "#offorder1Purpose"]);
  registerCallbackNextClick();
  registerCallbackFormInput();
  loadSession();
  updateNextButton();

  $("#offorder1WearDatetimepicker").data("DateTimePicker").minDate(moment().format("YYYY-MM-DD"));
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
} else {
  domLoaded();
}

const registerCallbackNextClick = () => {
  $("#btn-offorder1-next").on("click", e => {
    e.preventDefault();

    // .disabled 클래스일 경우 클릭 무시
    let $target = $(e.target);
    if ($target.hasClass("disabled")) {
      return false;
    }

    let phone = session.load("user").phone;
    if (!phone) {
      return false;
    }
    session.save(phone, getFormField());

    let reqUrl = new URL($target.data("url"), window.location.origin);

    // success
    window.location = reqUrl.href;

    return false;
  });
};

const registerCallbackFormInput = () => {
  $("#offorder1WearSelf").on("change", e => updateNextButton());
  $("#offorder1WearGender").on("change", e => updateNextButton());
  $("#offorder1WearDatetimepicker").on("dp.change", e => updateNextButton());
  $("#offorder1Purpose").on("change", e => updateNextButton());
  $("#offorder1Purpose2").on("change", e => updateNextButton());
};

const loadSession = () => {
  let phone = session.load("user").phone;
  if (!phone) {
    return false;
  }

  let data = session.load(phone);
  if (data.wear_self) {
    $("#offorder1WearSelf")[0].selectize.setValue(data.wear_self, false);
  }
  if (data.wear_gender) {
    $("#offorder1WearGender")[0].selectize.setValue(data.wear_gender, false);
  }
  if (data.wear_ymd) {
    $("#offorder1WearYmd").val(data.wear_ymd);
  }
  if (data.purpose) {
    $("#offorder1Purpose")[0].selectize.setValue(data.purpose, false);
  }
  if (data.purpose2) {
    $("#offorder1Purpose2").val(data.purpose2);
  }
};

const getFormField = () => {
  let formData = {
    wear_self: $("#offorder1WearSelf").val(),
    wear_gender: $("#offorder1WearGender").val(),
    wear_ymd: $("#offorder1WearYmd").val(),
    purpose: $("#offorder1Purpose").val(),
    purpose2: $("#offorder1Purpose2").val(),
  };
  for (let [key, value] of Object.entries(formData)) {
    if (!value) {
      continue;
    }
    formData[key] = value.trim();
  }

  return formData;
};

const validateForm = () => {
  let formData = getFormField();
  if (formData["wear_self"] === "self") {
    delete formData["wear_gender"];
  }

  let isValid = true;
  for (let [key, value] of Object.entries(formData)) {
    if (!value) {
      isValid = false;
      break;
    }
  }

  return isValid;
};

const updateNextButton = () => {
  let valWearSelf = $("#offorder1WearSelf").val();
  let wearGender = $("#offorder1WearGender")[0].selectize;
  if (valWearSelf === "self") {
    wearGender.clear();
    wearGender.disable();
  } else {
    wearGender.enable();
  }

  let $nextBtn = $("#btn-offorder1-next");
  let isFormValid = validateForm();
  if (isFormValid) {
    $nextBtn.html($nextBtn.data("label2")).removeClass("disabled");
  } else {
    $nextBtn.html($nextBtn.data("label1")).addClass("disabled");
  }
};
