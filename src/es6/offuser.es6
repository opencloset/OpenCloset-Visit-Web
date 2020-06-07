import "./lib/import-jquery";
import selectize from "./lib/selectize";
import session from "./lib/session";

const pageId = "offuser";

const domLoaded = () => {
  if (!$(`#page-${pageId}`).length) return;

  selectize.fixSelectizeReadonly(["#offuserBirth"]);
  registerCallbackCancelClick();
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

const registerCallbackCancelClick = () => {
  $("#btn-offuser-cancel").on("click", e => {
    e.preventDefault();

    // .disabled 클래스일 경우 클릭 무시
    let $target = $(e.target);
    if ($target.hasClass("disabled")) {
      return false;
    }

    let reqUrl = new URL($target.data("url"), window.location.origin);

    // success
    window.location = reqUrl.href;

    return false;
  });
};

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
    let data = session.load(phone);
    data.phone = phone;
    fetch(reqUrl, {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(data),
    })
      .then(response => response.json())
      .then(response => {
        let reqUrl = new URL($target.data("finish-url"), window.location.origin);
        reqUrl.searchParams.set("order_id", response.order.id);
        window.location = reqUrl.href;
      })
      .catch(error => {
        console.log("Error");
        console.log(error);
      });

    return false;
  });
};

const registerCallbackFormInput = () => {
  $("#offuserEmail").on("change", e => updateNextButton());
  $("#offuserBirth").on("change", e => updateNextButton());
  $("#offuserAddress2").on("change", e => updateNextButton());
  $("#offuserAddress4").on("change", e => updateNextButton());
};

const loadSession = () => {
  let phone = new URL(window.location.href).searchParams.get("phone");
  if (!phone) {
    return false;
  }

  let data = session.load(phone);
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
  if (data.address3) {
    $("#offuserAddress3").val(data.address3);
  }
  if (data.address4) {
    $("#offuserAddress4").val(data.address4);
  }
};

const getFormField = () => {
  let formData = {
    email: $("#offuserEmail").val(),
    birth: $("#offuserBirth").val(),
    address1: $("#offuserAddress1").val(),
    address2: $("#offuserAddress2").val(),
    address3: $("#offuserAddress3").val(),
    address4: $("#offuserAddress4").val(),
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
