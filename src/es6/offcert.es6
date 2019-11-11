import "./lib/import-jquery";
import bootbox from "bootbox/bootbox.all";

const domLoaded = () => {
  /**
   * 초기 상태
   */
  let resetAll = () => {
    $("input[name=certnum-realname]").val("").removeClass("state-invalid is-invalid").prop("disabled", false);
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
  resetAll();

  /**
   * 버튼 클릭: 다시 입력
   */
  $("#btn-input-reset").on("click", (e) => {
    e.preventDefault();
    resetAll();
    return false;
  });

  let updateToggleAll = () => {
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
    modal.animate({ scrollTop: 0 }, "slow");
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
    modal.animate({ scrollTop: 0 }, "slow");
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
    modal.animate({ scrollTop: 0 }, "slow");
    e.preventDefault();
    return false;
  });

  $("input[name=certnum-realname]").on("click", (e) => {
    $(e.target).removeClass("state-invalid is-invalid");
  });

  $("input[name=certnum-phone]").on("click", (e) => {
    $(e.target).removeClass("state-invalid is-invalid");
  });

  $("input[name=certnum-otp]").on("click", (e) => {
    $(e.target).removeClass("state-invalid is-invalid");
  });

  /**
   * 버튼 클릭: 인증 번호 발송
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
    let phone = $("input[name=certnum-phone]").val();
    if (!phone) {
      $("input[name=certnum-phone]").addClass("state-invalid is-invalid");
    }

    if (!(realname && phone)) {
      return false;
    }

    // success
    $(e.target).addClass("disabled");
    $("input[name=certnum-realname]").prop("disabled", true);
    $("input[name=certnum-phone]").prop("disabled", true);
    $("input[name=certnum-otp]").prop("disabled", false);
    $("input[name=certnum-otp]").focus();
    $("#btn-certnum-validate").removeClass("disabled");
    //...

    return false;
  });

  /**
   * 버튼 클릭: 인증 번호 확인
   */
  $("#btn-certnum-validate").on("click", (e) => {
    e.preventDefault();

    // .disabled 클래스일 경우 클릭 무시
    if ($(e.target).hasClass("disabled")) {
      return false;
    }

    let otp = $("input[name=certnum-otp]").val();
    if (!otp) {
      $("input[name=certnum-otp]").addClass("state-invalid is-invalid");
      return false;
    }

    // success
    $(e.target).addClass("disabled");
    $("input[name=certnum-otp]").prop("disabled", true);
    $("#btn-offcert-next").html($("#btn-offcert-next").data("label2")).removeClass("disabled");

    //...

    return false;
  });

  /**
   * 버튼 클릭: 다음 단계
   */
  $("#btn-offcert-next").on("click", (e) => {
    e.preventDefault();

    // .disabled 클래스일 경우 클릭 무시
    if ($(e.target).hasClass("disabled")) {
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
    //...

    return false;
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
}
else {
  domLoaded();
}
