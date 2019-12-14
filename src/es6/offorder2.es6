import "./lib/import-jquery";
import session from "./lib/session";

const pageId = "offorder2";

const domLoaded = () => {
  if (!$(`#page-${pageId}`).length) return;

  registerCallbackNextClick();
  registerCallbackFormInput();
  loadSession();
  updateNextButton();
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
} else {
  domLoaded();
}

const registerCallbackNextClick = () => {
  $("#btn-offorder2-next").on("click", e => {
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
    console.log(getFormField());

    let reqUrl = new URL($target.data("url"), window.location.origin);

    // success
    window.location = reqUrl.href;

    return false;
  });
};

const registerCallbackFormInput = () => {
  $("#offorder2PreferStyle").on("change", e => updateNextButton());
  $("#offorder2PreferColor").on("change", e => updateNextButton());
};

const loadSession = () => {
  let phone = new URL(window.location.href).searchParams.get("phone");
  if (!phone) {
    return false;
  }

  let data = session.load(phone, getFormField());
  if (data.prefer_style) {
    $("#offorder2PreferStyle")[0].selectize.setValue(data.prefer_style, false);
  }
  if (data.prefer_color) {
    $("#offorder2PreferColor")[0].selectize.setValue(data.prefer_color, false);
  }
};

const getFormField = () => {
  let formData = {
    prefer_style: $("#offorder2PreferStyle").val(),
    prefer_color: $("#offorder2PreferColor").val(),
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
  let $nextBtn = $("#btn-offorder2-next");
  let isFormValid = validateForm();
  if (isFormValid) {
    $nextBtn.html($nextBtn.data("label2")).removeClass("disabled");
  } else {
    $nextBtn.html($nextBtn.data("label1")).addClass("disabled");
  }
};
