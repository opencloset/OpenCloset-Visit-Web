import "./lib/import-jquery";
import session from "./lib/session";

const domLoaded = () => {
  registerCallbackNextClick();
  registerCallbackFormInput();
  updateNextButton();
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

    let phone = new URL(window.location.href).searchParams.get("phone");
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
  $("#wearDatetimepicker").on("dp.change", e => updateNextButton());
  $("#offorder1Purpose").on("change", e => updateNextButton());
  $("#offorder1Purpose2").on("change", e => updateNextButton());
};

const getFormField = () => {
  let formData = {
    wear_self: $("#offorder1WearSelf").val(),
    wear_gender: $("#offorder1WearGender").val(),
    wear_ymd: $("#wearYmd").val(),
    purpose: $("#offorder1Purpose").val(),
    purpose2: $("#offorder1Purpose2").val(),
  };
  for (let [key, value] of Object.entries(formData)) {
    if (!value) {
      continue;
    }
    formData[key] = value.trim();
  }
  console.log(formData);

  return formData;
};

const validateForm = () => {
  let formData = getFormField();

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
  let $nextBtn = $("#btn-offorder1-next");
  let isFormValid = validateForm();
  if (isFormValid) {
    $nextBtn.html($nextBtn.data("label2")).removeClass("disabled");
  } else {
    $nextBtn.html($nextBtn.data("label1")).addClass("disabled");
  }
};
