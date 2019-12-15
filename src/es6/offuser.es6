import "./lib/import-jquery";
import session from "./lib/session";

const pageId = "offuser";

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
  $("#btn-offuser-next").on("click", e => {
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
  $("#offuserEmail").on("change", e => updateNextButton());
  $("#offuserBirth").on("change", e => updateNextButton());
  $("#offuserAddress1").on("change", e => updateNextButton());
  $("#offuserAddress2").on("change", e => updateNextButton());
};

const loadSession = () => {
  let phone = new URL(window.location.href).searchParams.get("phone");
  if (!phone) {
    return false;
  }

  let data = session.load(phone, getFormField());
  if (data.email) {
    $("#offuserEmail").val(data.email);
  }
  if (data.birth) {
    $("#offuserBirth")[0].selectize.setValue(data.birth, false);
  }
  if (data.address1) {
    $("#offuserAddress1").val(data.address1);
  }
  if (data.address2) {
    $("#offuserAddress2").val(data.address2);
  }
};

const getFormField = () => {
  let formData = {
    email: $("#offuserEmail").val(),
    birth: $("#offuserBirth").val(),
    address1: $("#offuserAddress1").val(),
    address2: $("#offuserAddress2").val(),
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
  let $nextBtn = $("#btn-offuser-next");
  let isFormValid = validateForm();
  if (isFormValid) {
    $nextBtn.html($nextBtn.data("label2")).removeClass("disabled");
  } else {
    $nextBtn.html($nextBtn.data("label1")).addClass("disabled");
  }
};
