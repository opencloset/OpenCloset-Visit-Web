import "./lib/import-jquery";
import bootbox from "bootbox/bootbox.all";
import selectize from "./lib/selectize";
import session from "./lib/session";

const pageId = "offcert";

const domLoaded = () => {
  if (!$(`#page-${pageId}`).length) return;

  selectize.fixSelectizeReadonly(["#certnumGender"]);
  resetAll();
  registerCallback();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
}
else {
  domLoaded();
}

const resetAll = () => {
  // clear session
  session.clear();


  $("input[name=certnum-realname]").val("").removeClass("state-invalid is-invalid").prop("disabled", false);

  let $certnumGender = $("select[name=certnum-gender]")[0].selectize;
  $certnumGender.$control.removeClass("select-invalid");
  $certnumGender.clear(false);
  $certnumGender.enable();

  $("input[name=certnum-phone]").val("").removeClass("state-invalid is-invalid").prop("disabled", false);
  $("input[name=certnum-otp]").val("").removeClass("state-invalid is-invalid").prop("disabled", true);
  $("input[name=agree-service-checkbox]").prop("checked", false);
  $("input[name=agree-privacy-checkbox]").prop("checked", false);
  $("input[name=agree-all-checkbox]").prop("checked", false);

  $(".agree-service").removeClass("state-invalid is-invalid").addClass("agree-before-validate");
  $(".agree-privacy").removeClass("state-invalid is-invalid").addClass("agree-before-validate");

  $("#btn-certnum-send").removeClass("disabled");
  $("#btn-certnum-validate").addClass("disabled");
  $("#btn-offcert-next").addClass("disabled").html($("#btn-offcert-next").data("label1"));
};

const updateToggleAll = () => {
  let $toggleService = $("input[name=agree-service-checkbox]");
  let $togglePrivacy = $("input[name=agree-privacy-checkbox]");
  let $toggleAll = $("input[name=agree-all-checkbox]");
  if ( $toggleService.prop("checked") && $togglePrivacy.prop("checked") ) {
    $toggleAll.prop("checked", true);
  }
  else {
    $toggleAll.prop("checked", false);
  }
}

const registerCallback = () => {
  /**
   * 버튼 클릭: 다시 입력
   */
  $("#btn-input-reset").on("click", (e) => {
    e.preventDefault();
    resetAll();
    return false;
  });

  /**
   * 버튼 클릭: 모두 확인 후 동의
   */
  $(".agree-all").on("click", (e) => {
    $(".agree-service").removeClass("state-invalid is-invalid").addClass("agree-before-validate");
    $(".agree-privacy").removeClass("state-invalid is-invalid").addClass("agree-before-validate");

    let $toggle = $("input[name=agree-all-checkbox]");
    if ($toggle.prop("checked")) {
      $("input[name=agree-service-checkbox]").prop("checked", false);
      $("input[name=agree-privacy-checkbox]").prop("checked", false);
      updateToggleAll();
      e.preventDefault();
      return false;
    }

    let modal = bootbox.confirm({
      title: "서비스 이용 약관" + " / " + "개인 정보 취급 방침",
      message: $("#template-service").html() + "<hr>" + $("#template-privacy").html(),
      locale: "ko",
      buttons: {
        confirm: { label: "동의", className: "btn-primary" },
        cancel:  { label: "거부", className: "btn-danger"  },
      },
      callback: (result) => {
        if (result) {
          $("input[name=agree-service-checkbox]").prop("checked", true);
          $("input[name=agree-privacy-checkbox]").prop("checked", true);
        }
        else {
          $("input[name=agree-service-checkbox]").prop("checked", false);
          $("input[name=agree-privacy-checkbox]").prop("checked", false);
        }
        updateToggleAll();
        return true;
      }
    });
    e.preventDefault();
    return false;
  });

  /**
   * 버튼 클릭: 서비스 이용 약관
   */
  $(".agree-service").on("click", (e) => {
    $(".agree-service").removeClass("state-invalid is-invalid").addClass("agree-before-validate");

    let $toggle = $("input[name=agree-service-checkbox]");
    if ($toggle.prop("checked")) {
      $toggle.prop("checked", false);
      updateToggleAll();
      e.preventDefault();
      return false;
    }

    let modal = bootbox.confirm({
      title: "서비스 이용 약관",
      message: $("#template-service").html(),
      locale: "ko",
      buttons: {
        confirm: { label: "동의", className: "btn-primary" },
        cancel:  { label: "거부", className: "btn-danger"  },
      },
      callback: (result) => {
        if (result) {
          $toggle.prop("checked", true);
        }
        else {
          $toggle.prop("checked", false);
        }
        updateToggleAll();
        return true;
      }
    });
    e.preventDefault();
    return false;
  });

  /**
   * 버튼 클릭: 개인 정보 취급 방침
   */
  $(".agree-privacy").on("click", (e) => {
    $(".agree-privacy").removeClass("state-invalid is-invalid").addClass("agree-before-validate");

    let $toggle = $("input[name=agree-privacy-checkbox]");
    if ($toggle.prop("checked")) {
      $toggle.prop("checked", false);
      updateToggleAll();
      e.preventDefault();
      return false;
    }

    let modal = bootbox.confirm({
      title: "개인 정보 취급 방침",
      message: $("#template-privacy").html(),
      locale: "ko",
      buttons: {
        confirm: { label: "동의", className: "btn-primary" },
        cancel:  { label: "거부", className: "btn-danger"  },
      },
      callback: (result) => {
        if (result) {
          $toggle.prop("checked", true);
        }
        else {
          $toggle.prop("checked", false);
        }
        updateToggleAll();
        return true;
      }
    });
    e.preventDefault();
    return false;
  });

  $("input[name=certnum-realname]").on("click", (e) => {
    $(e.target).removeClass("state-invalid is-invalid");
  });

  $("select[name=certnum-gender]")[0].selectize.$wrapper.on("click", (e) => {
    $("select[name=certnum-gender]")[0].selectize.$control.removeClass("select-invalid");
  });

  $("input[name=certnum-phone]").on("click", (e) => {
    $(e.target).removeClass("state-invalid is-invalid");
  });

  $("input[name=certnum-otp]").on("click", (e) => {
    $(e.target).removeClass("state-invalid is-invalid");
  });

  /**
   * 버튼 클릭: 인증번호 발송
   */
  $("#btn-certnum-send").on("click", (e) => {
    e.preventDefault();

    // .disabled 클래스일 경우 클릭 무시
    if ($(e.target).hasClass("disabled")) {
      return false;
    }

    let realname = $("input[name=certnum-realname]").val();
    if (!realname) {
      $("input[name=certnum-realname]").addClass("state-invalid is-invalid");
    }

    let gender = $("select[name=certnum-gender]").val();
    if (!gender) {
      $("select[name=certnum-gender]")[0].selectize.$control.addClass("select-invalid");
    }

    let phone = $("input[name=certnum-phone]").val();
    if (!phone) {
      $("input[name=certnum-phone]").addClass("state-invalid is-invalid");
    }

    if (!(realname && gender && phone)) {
      return false;
    }

    let reqUrl = $(e.target).data("url");
    let data = new FormData();
    data.append("name", realname);
    data.append("to", phone);
    data.append("gender", gender);
    fetch(reqUrl, {
      method: "POST",
      headers: {
        "Accept": "application/json",
      },
      body: data,
    })
      .then(response => response.json())
      .then(response => {
        // success
        $(e.target).addClass("disabled");
        $("input[name=certnum-realname]").prop("disabled", true);
        $("select[name=certnum-gender]")[0].selectize.disable();
        $("input[name=certnum-phone]").prop("disabled", true);
        $("input[name=certnum-otp]").prop("disabled", false);
        $("input[name=certnum-otp]").focus();
        $("#btn-certnum-validate").removeClass("disabled");
      })
      .catch(error => {
        console.log("Error");
        console.log(error);
      });

    return false;
  });

  /**
   * 버튼 클릭: 인증번호 확인
   */
  $("#btn-certnum-validate").on("click", (e) => {
    e.preventDefault();

    // .disabled 클래스일 경우 클릭 무시
    if ($(e.target).hasClass("disabled")) {
      return false;
    }

    let realname = $("input[name=certnum-realname]").val();
    if (!realname) {
      $("input[name=certnum-realname]").addClass("state-invalid is-invalid");
    }

    let gender = $("select[name=certnum-gender]").val();
    if (!gender) {
      $("select[name=certnum-gender]")[0].selectize.$control.addClass("select-invalid");
    }

    let phone = $("input[name=certnum-phone]").val();
    if (!phone) {
      $("input[name=certnum-phone]").addClass("state-invalid is-invalid");
    }

    let otp = $("input[name=certnum-otp]").val();
    if (!otp) {
      $("input[name=certnum-otp]").addClass("state-invalid is-invalid");
      return false;
    }

    let reqUrl = $(e.target).data("url");
    let data = new FormData();
    data.append("name", realname);
    data.append("gender", gender);
    data.append("phone", phone);
    data.append("sms", otp);
    fetch(reqUrl, {
      method: "POST",
      headers: {
        "Accept": "application/json",
      },
      body: data,
    })
      .then(response => {
        if (response.status != 200) {
          class LoginError extends Error {
            constructor(...params) {
              super(...params)
              if (Error.captureStackTrace) {
                Error.captureStackTrace(this, LoginError);
              }
              this.name = "LoginError";
            }
          }
          return Promise.reject( new LoginError(`invalid http response ${response.status}`) );
        }
        return response.json();
      })
      .then(response => {
        // success
        $(e.target).addClass("disabled");
        $("input[name=certnum-realname]").prop("disabled", true);
        $("select[name=certnum-gender]")[0].selectize.disable();
        $("input[name=certnum-phone]").prop("disabled", true);
        $("input[name=certnum-otp]").prop("disabled", true);
        $("#btn-offcert-next").html($("#btn-offcert-next").data("label2")).removeClass("disabled");

        // save logged-in user info into client session storage
        let data = {
          phone: phone,
          name: realname,
          gender: gender,
        };
        session.save("user", data);
      })
      .catch(error => {
        console.log(`${error.name}: ${error.message}`);
      });

    return false;
  });

  /**
   * 버튼 클릭: 다음 단계
   */
  $("#btn-offcert-next").on("click", (e) => {
    e.preventDefault();

    // .disabled 클래스일 경우 클릭 무시
    let $target = $(e.target);
    if ($target.hasClass("disabled")) {
      return false;
    }

    let agreeService = $("input[name=agree-service-checkbox]").prop("checked");
    if (!agreeService) {
      $(".agree-service").removeClass("agree-before-validate").addClass("state-invalid is-invalid");
    }
    let agreePrivacy = $("input[name=agree-privacy-checkbox]").prop("checked");
    if (!agreePrivacy) {
      $(".agree-privacy").removeClass("agree-before-validate").addClass("state-invalid is-invalid");
    }

    if (!(agreeService && agreeService)) {
      return false;
    }

    // success
    window.location = $target.data("url");

    return false;
  });
};
